require 'csv'

class RecordsController < ApplicationController
  before_action :authorize_admin!, except: [:destroy]
  
  def export
    @table_name = params[:table]
    model = case @table_name
            when "grader_matches" then GraderMatch
            when "senior_grader_matches" then SeniorGraderMatch
            when "ta_matches" then TaMatch
            else nil
            end

    if model.nil?
      redirect_back fallback_location: root_path, alert: "Cannot export this table."
      return
    end

    records = model.includes(:applicant).all
    
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["Course Number", "Section", "Instructor", "Instructor Email", "Student", "Degree", "Student Email", "UIN", "Advisor"]
      records.each do |record|
        csv << [
          record.course_number,
          record.section,
          record.ins_name,
          record.ins_email,
          record.stu_name,
          record.applicant&.degree || "N/A",
          record.stu_email,
          record.uin,
          record.applicant&.advisor || "N/A"
        ]
      end
    end

    send_data csv_data, filename: "#{@table_name}_#{Date.today}.csv", type: "text/csv"
  end

  def perform_swap
    table = params[:table]
    model = case table
            when "grader_matches" then GraderMatch
            when "senior_grader_matches" then SeniorGraderMatch
            when "ta_matches" then TaMatch
            else nil
            end

    if model.nil?
      redirect_back fallback_location: root_path, alert: "Cannot swap in this table."
      return
    end

    model.transaction do
      from_record = model.find(params[:from_id])
      to_record = model.find(params[:to_id])

      # Capture original data
      from_data = {
        stu_name: from_record.stu_name,
        stu_email: from_record.stu_email,
        uin: from_record.uin
      }

      to_data = {
        stu_name: to_record.stu_name,
        stu_email: to_record.stu_email,
        uin: to_record.uin
      }

      # Step 1: Temporarily clear UIN on the first record to avoid unique constraint violation
      # We use update_columns to skip validations/callbacks for this temporary state
      from_record.update_columns(uin: nil)

      # Step 2: Update the second record with the first record's data
      to_record.update!(from_data)

      # Step 3: Update the first record with the second record's data
      from_record.update!(to_data)
    end

    redirect_to all_records_path(table: table), notice: "Assignments swapped successfully!"
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: root_path, alert: "One or both records not found."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
    redirect_back fallback_location: root_path, alert: "Swap failed: #{e.message}"
  end

  # Gets the records from the database
  def index
    @table_name = params[:table]
    case @table_name
    when "grader_matches"
      @records = GraderMatch.includes(:applicant).all
    when "recommendations"
      @records = Recommendation.all
    when "senior_grader_matches"
      @records = SeniorGraderMatch.includes(:applicant).all
    when "ta_matches"
      @records = TaMatch.includes(:applicant).all
    else
      @records = []
    end
    @records = @records.sort_by do |r|
      [r.confirm ? 0 : 1, r.assigned ? 0 : 1, r.course_number.to_i, r.section.to_i]
    end 
    @ta = Course.sum(:ta).to_i
    @senior_grader = Course.sum(:senior_grader).to_i
    @grader = Course.sum(:grader).to_i
  end

  # Admin function to toggle assignment
  def toggle_assignment
    model = params[:table].classify.constantize
    record = model.find(params[:id])
    record.update(assigned: !record.assigned)
    redirect_back fallback_location: root_path
  end

  # Admin function to revoke assignment
  def revoke_assignment
    model = params[:table].classify.constantize
    record = model.find(params[:id])
    # record.update(confirm: false)
    record.assigned = false
    record.confirm = false
    record.save!
    redirect_back(fallback_location: request.referer || root_path)
  end

  def manual_confirm
    model = params[:table].classify.constantize
    record = model.find(params[:id])
    record.update(confirm: true)
    redirect_back(fallback_location: request.referer || root_path)
  end

  # Admin function to mass unconfirm assignment
  def mass_confirm
    model = params[:table].classify.constantize
    model.find_each { |record|
      record.update(confirm: false)
    }
    redirect_back(fallback_location: request.referer || root_path)
  end

  # Admin function to mass toggle assignment send
  def mass_toggle_assignment
    model = params[:table].classify.constantize
    if model.where(assigned: true).exists?
      model.find_each { |record|
      record.update(assigned: false)
      }
      notice = "All assignments have been unsent."
    else
      model.find_each { |record|
      record.update(assigned: true)
      }
      notice = "All assignments have been sent."
    end
    redirect_back(fallback_location: request.referer || root_path)
  end

  def destroy_unconfirmed
    file_name = normalize_filename(params[:type])
    model_class = model_class_for(file_name)  # This gets the model based on file name

    unless model_class
      Rails.logger.error "No model class found for file: #{file_name}"
      flash[:alert] = "No model found for file #{file_name}."
      redirect_to view_csv_path and return
    end
   
    path = Rails.root.join("app", "Charizard", "util", "public", "output", "Modified_assignments.csv")
   
    unconfirmed = model_class.where(confirm: false)

    if unconfirmed.empty?
      Rails.logger.info "No unconfirmed assignments found"
      flash[:alert] = "No unconfirmed assignments found."
      redirect_back fallback_location: view_csv_path and return
    end

    uins = unconfirmed.pluck(:uin)

      uins.each do |uin|
        model_record = model_class.find_by(uin: uin)
        next unless model_record

        attributes = model_record.attributes.except("id", "created_at", "updated_at")
        headers = attributes.keys

        write_headers = !File.exist?(path) || File.zero?(path)

        CSV.open(path, "a", write_headers: write_headers, headers: headers) do |csv|
          csv << attributes.values
        end

        backup_unassigned_applicant(model_record.uin)
        update_new_needs_csv(file_name, model_record.course_number, model_record.section, model_record.ins_email)

        create_recommendation(model_record)
        model_record.destroy
        Rails.logger.debug "Record with UIN #{model_record.uin} destroyed."

      end


      flash[:notice] = "All unconfirmed assignments were deleted and processed."
      redirect_back fallback_location: view_csv_path
  end

  # This method is used to delete a record from the database
  def destroy
    file_name = normalize_filename(params[:file])
    model_class = model_class_for(file_name)  # This gets the model based on file name

    unless model_class
      Rails.logger.error "No model class found for file: #{file_name}"
      flash[:alert] = "No model found for file #{file_name}."
      redirect_to view_csv_path and return
    end

    # This creates a recommendation so the algorithm knows will not to reassign the same assignment
    @role = model_class.find(params[:id])
    if @role.nil?
      Rails.logger.error "No Role: #{@role.inspect}"
      flash[:alert] = "No Role: #{@role.inspect}"
      redirect_to all_records_path(table: "ta_matches") and return
    end
    Rails.logger.debug "Role: #{@role.inspect}"
    create_recommendation(@role)

    # This is created if the student denys the position
    create_withdrawal_request(@role) if params[:deny].present?

    # Find the record in the DB
    model_record = model_class.find_by(uin: @role.uin)
    if model_record
      # This creates a backup of the unassigned applicant in DB and csv
      # Then the new course needs file is updated and the record is deleted
      if params[:deny].present?
        add_deny_to_modified_assignments(file_name, model_record)
      else
        add_to_modified_assignments(file_name, model_record)
      end

      backup_unassigned_applicant(@role.uin)
      update_new_needs_csv(file_name, @role.course_number, @role.section, @role.ins_email)
      model_record.destroy
      flash[:notice] = "Student record deleted. Class details saved separately."

      respond_to do |format|
        format.js
        format.html do
          if session[:role] == "admin"
            redirect_to all_records_path(table: params[:file])
          elsif session[:role] == "student"
            redirect_to new_withdrawal_request_path
          else
            redirect_to root_path
          end
        end
      end
      Rails.logger.debug "Record with UIN #{@role.uin} destroyed."
    else
      Rails.logger.debug "No record found with UIN #{@role.uin}"
    end
  end
  
  def backup_unassigned_applicant(uin)
    applicant = Applicant.find_by(uin: uin)
    return unless applicant

    UnassignedApplicant.create(applicant.attributes.except("id", "created_at", "updated_at", "confirm"))
  end

  def update_new_needs_csv(file_name, course_number, section, instructor_email)
    course = Course.where("course_number LIKE ?", "%#{course_number}%")
                   .where("section LIKE ?", "%#{section}%").where("faculty_email LIKE ?", "%#{instructor_email}%").first
    return unless course

    assignment_type = determine_assignment_type(file_name)
    path = Rails.root.join("app", "Charizard", "util", "public", "output", "New_Needs.csv")
    column_order = [ "Course_Name", "Course_Number", "Section", "Instructor", "Faculty_Email", "TA", "Senior_Grader", "Grader", "Professor Pre-Reqs" ]

    data = File.exist?(path) ? CSV.read(path, headers: true).map(&:to_h) : []
    entry = data.find { |row| row["Course_Number"] == course.course_number && row["Section"] == course.section }

    if entry
      entry[assignment_type] = (entry[assignment_type].to_i + 1).to_s
    else
      new_entry = {
        "Course_Name" => course.course_name,
        "Course_Number" => course.course_number,
        "Section" => course.section,
        "Instructor" => course.instructor,
        "Faculty_Email" => course.faculty_email,
        "TA" => "0", "Senior_Grader" => "0", "Grader" => "0",
        "Professor Pre-Reqs" => course.pre_reqs.presence || "N/A"
      }
      new_entry[assignment_type] = "1"
      data << new_entry
    end

    CSV.open(path, "w", headers: column_order, write_headers: true) do |csv|
      data.each { |row| csv << row.values_at(*column_order) }
    end
  end

  # This updates the new needs file accordingly
  # The new_needs file needs to be updated based on the open position it has for each job
  # So it updates the TA, Senior Grader, and Grader columns with the correct number based on the file name
  def determine_assignment_type(file_name)
    {
      "TA_Matches.csv" => "TA",
      "Senior_Grader_Matches.csv" => "Senior_Grader",
      "Grader_Matches.csv" => "Grader"
    }[file_name]
  end

  def add_to_modified_assignments(file_name, model_record)
    path = Rails.root.join("app", "Charizard", "util", "public", "output", "Modified_assignments.csv")
    if model_record.present?
      attributes = model_record.attributes.except("id", "created_at", "updated_at")
      headers = attributes.keys

      write_headers = !File.exist?(path) || File.zero?(path)

      CSV.open(path, "a", write_headers: write_headers, headers: headers) do |csv|
        csv << attributes.values
      end
    end
  end

  def add_deny_to_modified_assignments(file_name, model_record)
    path = Rails.root.join("app", "Charizard", "util", "public", "output", "Modified_assignments.csv")
    return unless model_record.present?

    # Extract attributes and add the 'deny' field
    attributes = model_record.attributes.except("id", "created_at", "updated_at")
    attributes["deny"] = "applicant declined the position"

    headers = attributes.keys
    write_headers = !File.exist?(path) || File.zero?(path)

    CSV.open(path, "a", write_headers: write_headers, headers: headers) do |csv|
      csv << attributes.values
    end
  end
end


  def un_confirmed_params(type)
    case type
    when "ta_matches"
      { file_name: "TA_Matches.csv", model_class: TaMatch }
    when "grader_matches"
      { file_name: "Grader_Matches.csv", model_class: GraderMatch }
    when "senior_grader_matches"
      { file_name: "Senior_Grader_Matches.csv", model_class: SeniorGraderMatch }
    else
      flash[:alert] = "Invalid type"
      redirect_back fallback_location: view_csv_path and return
    end
  end

  # Used to transform the file name to the correct format
  def normalize_filename(file_param)
    case "#{file_param}.csv"
    when "ta_matches.csv" then "TA_Matches.csv"
    when "senior_grader_matches.csv" then "Senior_Grader_Matches.csv"
    when "grader_matches.csv" then "Grader_Matches.csv"
    else "#{file_param}.csv"
    end
  end

  # Used to get the model class based on the file name
  def model_class_for(file_name)
    {
      "TA_Matches.csv" => TaMatch,
      "Grader_Matches.csv" => GraderMatch,
      "Senior_Grader_Matches.csv" => SeniorGraderMatch
    }[file_name]
  end

  # this creastes a recommendation based on the params
  def create_recommendation(role)
    Recommendation.create(
      email: role.ins_email,
      name: role.ins_name,
      course: "CSCE #{role.course_number}",
      selectionsTA: "#{role.stu_name} (#{role.stu_email})",
      feedback: "I do not want to work with this student",
      additionalfeedback: "Auto Generated by Admin for Algorithm",
      admin: true
    )
  end

  # This method is used to create a withdrawal request
  def create_withdrawal_request(role)
    request = WithdrawalRequest.create(
      student_email: role.stu_email,
      student_name: role.stu_name,
      course_number: role.course_number,
      section_id: role.section,
      instructor_email: role.ins_email,
      instructor_name: role.ins_name,
    )

    if request.persisted?
      flash[:notice] = "TA assignment deleted and withdrawal request created."
    else
      flash[:alert] = "TA assignment deleted, but unable to create withdrawal request."
    end
  end

  def read_csv(file_name)
    csv_data = []
    file_path = Rails.root.join("app", "Charizard", "util", "public", "output", file_name)
    CSV.foreach(file_path, headers: true) do |row|
      csv_data << row.to_h
    end
    csv_data
  end
  # This finds a record in the csv file based on the uin
  def find_record_in_csv(file_name, uin)
    records = read_csv(file_name)
    records.find { |r| r["UIN"] == uin }
  end

  # This adds the record to the modified assignments csv
  def move_to_modified_assignments(file_name, record)
    path = Rails.root.join("app", "Charizard", "util", "public", "output", "Modified_assignments.csv")
    CSV.open(path, "a", headers: record.keys, write_headers: !File.exist?(path)) do |csv|
      csv << record.values
    end
  end

  def update_csv(file_name, uin)
    records = read_csv(file_name).reject { |r| r["UIN"] == uin }
    file_path = Rails.root.join("app", "Charizard", "util", "public", "output", file_name)

    CSV.open(file_path, "w", headers: records.first&.keys || [], write_headers: true) do |csv|
      records.each { |r| csv << r.values }
    end
  end

  # This adds the student in the unassigned applicants table and cvs
 

  # This is the column mappiing for adding a student to the unassigned applicants csv
  # This is needed beacuse the table and the csv have different column names
  def backup_applicant_column_mapping
    column_order = [
      "Timestamp", "Email Address", "First and Last Name", "UIN", "Phone Number", "How many hours do you plan to be enrolled in?",
      "Degree Type?", "1st Choice Course", "2nd Choice Course", "3rd Choice Course", "4th Choice Course", "5th Choice Course",
      "6th Choice Course", "7th Choice Course", "8th Choice Course", "9th Choice Course", "10th Choice Course", "GPA",
      "Country of Citizenship?", "English language certification level?", "Which courses have you taken at TAMU?",
      "Which courses have you taken at another university?", "Which courses have you TAd for?", "Who is your advisor (if applicable)?",
      "What position are you applying for?"
    ]

    mapping = {
      "Timestamp" => "timestamp", "Email Address" => "email", "First and Last Name" => "name", "UIN" => "uin",
      "Phone Number" => "number", "How many hours do you plan to be enrolled in?" => "hours", "Degree Type?" => "degree",
      "1st Choice Course" => "choice_1", "2nd Choice Course" => "choice_2", "3rd Choice Course" => "choice_3",
      "4th Choice Course" => "choice_4", "5th Choice Course" => "choice_5", "6th Choice Course" => "choice_6",
      "7th Choice Course" => "choice_7", "8th Choice Course" => "choice_8", "9th Choice Course" => "choice_9",
      "10th Choice Course" => "choice_10", "GPA" => "gpa", "Country of Citizenship?" => "citizenship",
      "English language certification level?" => "cert", "Which courses have you taken at TAMU?" => "prev_course",
      "Which courses have you taken at another university?" => "prev_uni", "Which courses have you TAd for?" => "prev_ta",
      "Who is your advisor (if applicable)?" => "advisor", "What position are you applying for?" => "positions"
    }

    [ column_order, mapping ]
  end

  # This updates the new needs file accordingly
  # THe new_needs file need to be updated base on the open position it has for each job
  # So it updates the TA, Senior Grader and Grader columns with the correct number based on the file name
  private
  # THis is for the new needs file that will get the file and respond with the corresponding column
  def determine_assignment_type1(record)
    case record
    when "TA_Matches.csv" then "TA"
    when "Senior_Grader_Matches.csv" then "Senior_Grader"
    when "Grader_Matches.csv" then "Grader"
    end
  end
  

