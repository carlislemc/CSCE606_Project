# frozen_string_literal: true

# This controller manages the the main assignment process of the application
# It handles the CSV processing, viewing, editing, and updating of TA assignments.
class TaAssignmentsController < ApplicationController
  require "csv"

  before_action :authorize_admin!

  # This is the main function that handles the CSV processing for the first time
  def process_csvs
    delete_all_csvs

    apps_csv = generate_csv_apps(Applicant.all)
    apps_csv_path = Rails.root.join("tmp", "TA_Applicants.csv")
    File.write(apps_csv_path, apps_csv)

    needs_csv = generate_csv_needs(Course.all)
    needs_csv_path = Rails.root.join("tmp", "TA_Needs.csv")
    File.write(needs_csv_path, needs_csv)

    recs_csv = generate_csv_recommendations(Recommendation.all)
    recs_csv_path = Rails.root.join("tmp", "Prof_Prefs.csv")
    File.write(recs_csv_path, recs_csv)

    python_path = `which python3`.strip  # Find Python path dynamically
    puts "Python Path: #{python_path}"  # Check if this is correct
    system("#{python_path} app/Charizard/main.py '#{apps_csv_path}' '#{needs_csv_path}' '#{recs_csv_path}'")

    flash[:notice] = "Json processing complete"

    system("bundle exec rake import:standard_json")
    file_paths = [
      "app/Charizard/util/public/output/TA_Matches.csv",
      "app/Charizard/util/public/output/Senior_Grader_Matches.csv",
      "app/Charizard/util/public/output/Grader_Matches.csv",
      "app/Charizard/util/public/output/Modified_assignments.csv"
    ]

    file_paths.each do |path|
      full_path = Rails.root.join(path)
      File.delete(full_path) if File.exist?(full_path)
    end
    update_needs_from_assignments
    

    # created for viewing
    unapps_csv = generate_csv_apps(UnassignedApplicant.all)
    unapps_csv_path = Rails.root.join("app", "Charizard", "util", "public", "output", "Unassigned_Applicants.csv")
    File.write(unapps_csv_path, unapps_csv)

    calibrate_unassigned_applicants
  end
  
  # This method is used to view the CSV files
  def view_csv
    csv_directory = Rails.root.join("app", "Charizard", "util", "public", "output")
    @csv_files = Dir.entries(csv_directory).select { |f| f.end_with?(".csv") }

    if params[:file].present? && @csv_files.include?(params[:file])
      @selected_csv = params[:file]

      case @selected_csv
      when "Unassigned_Applicants.csv"
        unass_apps_csv = generate_csv_apps(UnassignedApplicant.all)
        unass_apps_csv_path = Rails.root.join("app", "Charizard", "util", "public", "output","Unassigned_Applicants.csv")
        File.write(unass_apps_csv_path, unass_apps_csv)
      end
  
      @csv_content = read_csv(File.join(csv_directory, @selected_csv))
    end
  end

  # This is to edit the assignments and get the data from the model
  def edit

    file_name = params[:file] + ".csv"
    @table_name = params[:file]

    case file_name
    when "ta_matches.csv"
      file_name = "TA_Matches.csv"
    when "senior_grader_matches.csv"
      file_name = "Senior_Grader_Matches.csv"
    when "grader_matches.csv"
      file_name = "Grader_Matches.csv"
    end
    csv_mappings = {
      "TA_Matches.csv" => TaMatch,
      "Grader_Matches.csv" => GraderMatch,
      "Senior_Grader_Matches.csv" => SeniorGraderMatch
    }

    model_class = csv_mappings[file_name]
  
    @record = model_class.find_by(uin: params[:uin])
    if @record.nil?
      redirect_to view_csv_path, alert: "Record not found."
    end
  end

  # This method is used to update the assignments
  def update
    file_key = params[:file]&.strip&.downcase
    return redirect_back(fallback_location: root_path, alert: "Invalid file key.") if file_key.blank?

    csv_directory = Rails.root.join("app", "Charizard", "util", "public", "output")

    # Mapping file_key to actual file name
    file_name = case file_key
                when "ta_matches" then "TA_Matches.csv"
                when "senior_grader_matches" then "Senior_Grader_Matches.csv"
                when "grader_matches" then "Grader_Matches.csv"
                else "#{params[:file]}.csv"
                end

    csv_mappings = {
      "TA_Matches.csv" => TaMatch,
      "Grader_Matches.csv" => GraderMatch,
      "Senior_Grader_Matches.csv" => SeniorGraderMatch
    }

    model_class = csv_mappings[file_name]
    unless model_class
      return redirect_back(fallback_location: root_path, alert: "Unsupported file type: #{file_name}")
    end
    modified_class_csv_path = csv_directory.join("Modified_assignments.csv")

    # Find the current record
    @record = model_class.find_by(course_number: params[:course_number], section: params[:section])
    if @record.present?
      attributes = @record.attributes.except("id", "created_at", "updated_at")
      headers = attributes.keys

      write_headers = !File.exist?(modified_class_csv_path) || File.zero?(modified_class_csv_path)

      CSV.open(modified_class_csv_path, "a", write_headers: write_headers, headers: headers) do |csv|
        csv << attributes.values
      end
    else
      Rails.logger.debug "No matching @record found to write to CSV"
      return redirect_back(fallback_location: root_path, alert: "Matching record not found.")
    end

  
    # Backup applicant to UnassignedApplicant
    if @record.uin.present?
      applicant = Applicant.find_by(uin: @record.uin)
      if applicant
        UnassignedApplicant.create(applicant.attributes.except("id", "created_at", "updated_at", "confirm"))
      end
    end
  
    # Update record with new values
    if @record.update(
      stu_name: params[:stu_name],
      stu_email: params[:stu_email],
      uin: params[:uin]
    )
      # Remove new assignment from unassigned list
      if (new_uin = params[:uin]).present?
        prev_app = UnassignedApplicant.find_by(uin: new_uin)
        prev_app&.destroy
      end
  
      flash[:notice] = "Student information updated successfully."
    else
      flash[:alert] = "Failed to update student info."
    end
  
    redirect_to all_records_path(table: file_key)
  end
  def determine_assignment_type(record)
    case record
    when "TA_Matches.csv" then "TA"
    when "Senior_Grader_Matches.csv" then "Senior_Grader"
    when "Grader_Matches.csv" then "Grader"
    end
  end

  # Used to download the CSV files
  def download_csv
    file_name = params[:file]
    file_path = Rails.root.join("app", "Charizard", "util", "public", "output", file_name)
    if File.exist?(file_path)
      send_file file_path, filename: file_name, type: "text/csv", disposition: "attachment"
    else
      redirect_to root_path, alert: "File not found."
    end
  end

  # Deletes all of the relevant assignment csvs and models excluding withdrawls
  def delete_all_csvs(skip_redirect: false)
    Dir[Rails.root.join("app/Charizard/util/public/output/*.csv")].each do |file|
      File.delete(file) if File.exist?(file)
    end

    ["TA_Matches.csv", "Grader_Matches.csv", "Senior_Grader_Matches.csv"].each do |fname|
      tmp_path = Rails.root.join("tmp", fname)
      File.delete(tmp_path) if File.exist?(tmp_path)
    end
    GraderMatch.delete_all
    SeniorGraderMatch.delete_all
    TaMatch.delete_all
    UnassignedApplicant.delete_all

  end

  # Used to get a final csvs with all of the assignments with relevant applicant data
  def export_final_csv
    confirmed_only = ActiveModel::Type::Boolean.new.cast(params[:confirmed_only])

    headers = [ "Assignment", "Course Number", "Section ID", "Instructor Name",
                "Instructor Email", "Student Name", "Student Email", "UIN", "Phone Number",
                "Enrollment hours", "Degree", "Country of Citizenship", "English Certification Level","Advisor" ]

    final_csv_path = Rails.root.join("app", "Charizard", "util", "public", "output", "Assignments(#{Date.today}).csv")

    assignment_header_mapping = {
      "Course Number" => "course_number",
      "Section ID" => "section",
      "Instructor Name" => "ins_name",
      "Instructor Email" => "ins_email",
      "Student Name" => "stu_name",
      "Student Email" => "stu_email",
      "UIN"=> "uin"
    }

    models = {
      "TA" => TaMatch,
      "Grader" => GraderMatch,
      "Senior Grader" => SeniorGraderMatch
    }

    applicants_by_uin = Applicant.all.index_by { |applicant| applicant.uin.to_s }

    CSV.open(final_csv_path, "w") do |csv|
      csv << headers
      models.each do |assignment_type, model|
        export_option = confirmed_only ? model.where(confirm: true) : model.all
        export_option.find_each do |assignment|
          uin = assignment.uin.to_i
          applicant = applicants_by_uin[uin.to_s]
          Rails.logger.debug("Applicant: #{applicant.inspect}")

          row_data = headers.map do |header|
            case header
            when "Assignment"
              assignment_type
            when *assignment_header_mapping.keys
              assignment.send(assignment_header_mapping[header])
            when "Phone Number"
              applicant.number
            when "Enrollment hours"
              applicant.hours
            when "Degree"
              applicant.degree
            when "Country of Citizenship"
              applicant.citizenship
            when "English Certification Level"
              applicant.cert
            when "Advisor"
              applicant.advisor
            else
              ""
            end
          end
          csv << row_data
        end
      end
    end

    flash[:notice] = "Assignments.csv has been successfully created!"
    send_file final_csv_path, filename: "Assignments(#{Date.today}).csv", type: "text/csv", disposition: "attachment"
  end

  def update_needs_from_assignments
    path = Rails.root.join("app", "Charizard", "util", "public", "output", "New_Needs.csv")
    column_order = [ "Course_Name", "Course_Number", "Section", "Instructor", "Faculty_Email", "TA", "Senior_Grader", "Grader", "Professor Pre-Reqs" ]

    data = File.exist?(path) ? CSV.read(path, headers: true).map(&:to_h) : []

    Course.find_each do |course|
      assigned_tas = TaMatch.where(
        "LOWER(?) LIKE '%' || LOWER(course_number) || '%' AND LOWER(?) LIKE '%' || LOWER(section) || '%'",
        course.course_number.to_s,
        course.section.to_s
      ).count
      assigned_graders = GraderMatch.where(
        "LOWER(?) LIKE '%' || LOWER(course_number) || '%' AND LOWER(?) LIKE '%' || LOWER(section) || '%'",
        course.course_number.to_s,
        course.section.to_s
      ).count
      assigned_senior_graders = SeniorGraderMatch.where(
        "LOWER(?) LIKE '%' || LOWER(course_number) || '%' AND LOWER(?) LIKE '%' || LOWER(section) || '%'",
        course.course_number.to_s,
        course.section.to_s
      ).count

      remaining_tas = [(course.ta.to_f.round - assigned_tas), 0].max
      remaining_senior_graders = [(course.senior_grader.to_f.round - assigned_senior_graders), 0].max
      remaining_graders = [(course.grader.to_f.round - assigned_graders), 0].max
  
      # Skip this course if no more help is needed
      next if remaining_tas == 0 && remaining_senior_graders == 0 && remaining_graders == 0
  
      entry = data.find { |row| row["Course_Number"] == course.course_number && row["Section"] == course.section }
  
      if entry
        entry["TA"] = remaining_tas.to_s
        entry["Senior_Grader"] = remaining_senior_graders.to_s
        entry["Grader"] = remaining_graders.to_s
      else
        data << {
          "Course_Name" => course.course_name,
          "Course_Number" => course.course_number,
          "Section" => course.section,
          "Instructor" => course.instructor,
          "Faculty_Email" => course.faculty_email,
          "TA" => remaining_tas.to_s,
          "Senior_Grader" => remaining_senior_graders.to_s,
          "Grader" => remaining_graders.to_s,
          "Professor Pre-Reqs" => course.pre_reqs.presence || "N/A"
        }
      end
    end
  
    # Write once after processing all courses
    CSV.open(path, "w", headers: column_order, write_headers: true) do |csv|
      data.each { |row| csv << row.values_at(*column_order) }
    end
  end

  def calibrate_unassigned_applicants
    UnassignedApplicant.destroy_all

    grader_uins = GraderMatch.pluck(:uin).map(&:to_i)
    senior_grader_uins = SeniorGraderMatch.pluck(:uin).map(&:to_i)
    ta_uins = TaMatch.pluck(:uin).map(&:to_i)

    blacklist_emails = Blacklist.pluck(:student_email).map { |e| e.to_s.downcase.strip }.to_set
    blacklist_names = Blacklist.pluck(:student_name).map { |n| n.to_s.downcase.strip }.to_set

    seen_keys = Set.new

    Applicant.find_each do |applicant|
      name_key = applicant.name.to_s.strip.downcase
      email_key = applicant.email.to_s.strip.downcase
      uin_key = applicant.uin.to_i
      next if grader_uins.include?(applicant.uin) ||
                senior_grader_uins.include?(applicant.uin) ||
                ta_uins.include?(applicant.uin) ||
                blacklist_emails.include?(email_key) ||
                blacklist_names.include?(name_key)

    dup_key = uin_key  

    next if seen_keys.include?(dup_key)

    seen_keys.add(dup_key)

      UnassignedApplicant.create!(
        timestamp: applicant.timestamp,
        email: applicant.email,
        name: applicant.name,
        uin: applicant.uin,
        number: applicant.number,
        hours: applicant.hours,
        degree: applicant.degree,
        choice_1: applicant.choice_1,
        choice_2: applicant.choice_2,
        choice_3: applicant.choice_3,
        choice_4: applicant.choice_4,
        choice_5: applicant.choice_5,
        choice_6: applicant.choice_6,
        choice_7: applicant.choice_7,
        choice_8: applicant.choice_8,
        choice_9: applicant.choice_9,
        choice_10: applicant.choice_10,
        gpa: applicant.gpa,
        citizenship: applicant.citizenship,
        cert: applicant.cert,
        prev_course: applicant.prev_course,
        prev_uni: applicant.prev_uni,
        prev_ta: applicant.prev_ta,
        advisor: applicant.advisor,
        positions: applicant.positions
      )
    end
    redirect_to view_csv_path and return
  end

  private
  # These are the methods used to import the csvs into the models from the algorithm
  # This method is used to import the unassigned applicants

  def save_uploaded_file(file)
    path = Rails.root.join("tmp", file.original_filename)
    File.open(path, "wb") { |f| f.write(file.read) }
    path
  end

  def read_csv(file_name)
    csv_data = []
    file_path = Rails.root.join("app", "Charizard", "util", "public", "output", file_name)
    CSV.foreach(file_path, headers: true) do |row|
      csv_data << row.to_h
    end
    csv_data
  end

  # This method is used to generate the CSV files for the needs
  def generate_csv_needs(records)
    CSV.generate(headers: true) do |csv|
    csv << [ "Course_Name", "Course_Number", "Section", "Instructor", "Faculty_Email", "TA", "Senior_Grader", "Grader", "Professor Pre-Reqs" ]
    records.each do |record|
      csv << [
        record.course_name,
        record.course_number,
        record.section,
        record.instructor,
        record.faculty_email,
        record.ta.to_f,
        record.senior_grader.to_f,
        record.grader.to_f,
        record.pre_reqs || "N/A"
      ]
      end
    end
  end

  # This method is used to generate the CSV files for the recommendations
  def generate_csv_recommendations(records)
    CSV.generate(headers: true) do |csv|
      csv << [ "Timestamp", "Email Address", "Your Name (first and last)", "Select a TA/Grader", "Course (e.g. CSCE 421)", "Feedback", "Additional Feedback about this student" ]
      records.each do |record|
        csv << [
          record.created_at.strftime("%m/%d/%Y %H:%M:%S"),
          record.email,
          record.name,
          record.selectionsTA,
          record.course,
          record.feedback,
          record.additionalfeedback
        ]
      end
    end
  end

  # This method is used to generate the CSV files for the applications
  def generate_csv_apps(records)
    blacklist_emails = Blacklist.pluck(:student_email).map { |e| e.to_s.downcase.strip }.to_set
    blacklist_names = Blacklist.pluck(:student_name).map { |n| n.to_s.downcase.strip }.to_set

    CSV.generate(headers: true) do |csv|
    csv << [ "Timestamp", "Email Address", "First and Last Name", "UIN", "Phone Number", "How many hours do you plan to be enrolled in?", "Degree Type?", "1st Choice Course", "2nd Choice Course", "3rd Choice Course", "4th Choice Course", "5th Choice Course", "6th Choice Course", "7th Choice Course", "8th Choice Course", "9th Choice Course", "10th Choice Course", "GPA", "Country of Citizenship?", "English language certification level?", "Which courses have you taken at TAMU?", "Which courses have you taken at another university?", "Which courses have you TAd for?", "Who is your advisor (if applicable)?", "What position are you applying for?" ]
    records.each do |record|
      name_key = record.name.to_s.strip.downcase
      email_key = record.email.to_s.strip.downcase

      next if blacklist_emails.include?(email_key) || blacklist_names.include?(name_key) 
      csv << [
        record.timestamp,
        record.email,
        record.name,
        record.uin.to_i,
        record.number,
        record.hours.to_i,
        record.degree,
        record.choice_1.to_i,
        record.choice_2.to_i,
        record.choice_3.to_i,
        record.choice_4.to_i,
        record.choice_5.to_i,
        record.choice_6.to_i,
        record.choice_7.to_i,
        record.choice_8.to_i,
        record.choice_9.to_i,
        record.choice_10.to_i,
        record.gpa.to_f,
        record.citizenship,
        record.cert.to_i,
        record.prev_course,
        record.prev_uni,
        record.prev_ta,
        record.advisor,
        record.positions
      ]
      end
    end
  end

  def authorize_admin!
    case session[:role].to_s
    when "admin"
    else
      redirect_to root_path, alert: "Unauthorized access."
    end
  end
end