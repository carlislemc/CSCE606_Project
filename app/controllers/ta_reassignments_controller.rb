# frozen_string_literal: true

# This controller manages the reassignment process of the application
# This is used to process the db after the admin as made modifications to the assignments
# and there ends up being a need for reassignment such as a student or admin deleting their
# assignment. This will allow the algorithm to run again and reassign the students that are
# Left over to classes that still need to be filled out while saving the previous confirmed assignments
class TaReassignmentsController < ApplicationController
  require "csv"
  before_action :authorize_admin!
  # main function to process the reassignment functionality
  def process_csvs
    unass_apps_csv = generate_csv_apps(UnassignedApplicant.all)
    unass_apps_csv_path = Rails.root.join("app", "Charizard", "util", "public", "output","Unassigned_Applicants.csv")
    File.write(unass_apps_csv_path, unass_apps_csv)

    update_needs_from_assignments

    needs_csv_path = Rails.root.join("app/Charizard/util/public/output", "New_Needs.csv")

    recs_csv = generate_csv_recommendations(Recommendation.all)
    recs_csv_path = Rails.root.join("tmp", "Prof_Prefs.csv")
    File.write(recs_csv_path, recs_csv)

    python_path = `which python3`.strip  # Find Python path dynamically
    # calls the python script to process the csv files
    system("#{python_path} app/Charizard/main.py '#{unass_apps_csv_path}' '#{needs_csv_path}' '#{recs_csv_path}'")

    flash[:notice] = "CSV processing complete"

    File.delete(Rails.root.join("app/Charizard/util/public/output/New_Needs.csv"))

    update_needs_from_assignments

    calibrate_unassigned_applicants

    redirect_to view_csv_path
  end

  def update_needs_from_assignments
    path = Rails.root.join("app", "Charizard", "util", "public", "output", "New_Needs.csv")
    column_order = [ "Course_Name", "Course_Number", "Section", "Instructor", "Faculty_Email", "TA", "Senior_Grader", "Grader", "Professor Pre-Reqs" ]

    data = []

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

      next if remaining_tas == 0 && remaining_senior_graders == 0 && remaining_graders == 0

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

    CSV.open(path, "w", headers: column_order, write_headers: true) do |csv|
      data.each { |row| csv << row.values_at(*column_order) }
    end
  end
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

  def generate_csv_apps(records)
    blacklist_emails = Blacklist.pluck(:student_email).map { |e| e.to_s.downcase.strip }.to_set
    blacklist_names = Blacklist.pluck(:student_name).map { |n| n.to_s.downcase.strip }.to_set

    seen_keys = Set.new

    CSV.generate(headers: true) do |csv|
    csv << [ "Timestamp", "Email Address", "First and Last Name", "UIN", "Phone Number", "How many hours do you plan to be enrolled in?", "Degree Type?", "1st Choice Course", "2nd Choice Course", "3rd Choice Course", "4th Choice Course", "5th Choice Course", "6th Choice Course", "7th Choice Course", "8th Choice Course", "9th Choice Course", "10th Choice Course", "GPA", "Country of Citizenship?", "English language certification level?", "Which courses have you taken at TAMU?", "Which courses have you taken at another university?", "Which courses have you TAd for?", "Who is your advisor (if applicable)?", "What position are you applying for?" ]
    records.each do |record|
      name_key = record.name.to_s.strip.downcase
      email_key = record.email.to_s.strip.downcase
      uin_key = record.uin.to_i

      next if blacklist_emails.include?(email_key) || blacklist_names.include?(name_key)

      dup_key = uin_key  # or [name_key, email_key]

      next if seen_keys.include?(dup_key)

      seen_keys.add(dup_key)
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

  def calibrate_unassigned_applicants(*)
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

    dup_key = uin_key  # or [name_key, email_key]

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
  end

  def view_csv
    csv_directory = Rails.root.join("app", "Charizard", "util", "public", "output")
    @csv_files = Dir.entries(csv_directory).select { |f| f.end_with?(".csv") }

    if params[:file].present? && @csv_files.include?(params[:file])
      @selected_csv = params[:file]
      @csv_content = read_csv(File.join(csv_directory, @selected_csv))
    end
  end

  def download_csv
    file_name = params[:file]
    file_path = Rails.root.join("app", "Charizard", "output", file_name)
    if File.exist?(file_path)
      send_file file_path, filename: file_name, type: "text/csv", disposition: "attachment"
    else
      redirect_to root_path, alert: "File not found."
    end
  end

  private
  def authorize_admin!
    case session[:role].to_s
    when "admin"
    else
      redirect_to root_path, alert: "Unauthorized access."
    end
  end

  def read_csv(file_path)
    csv_data = []
    CSV.foreach(file_path, headers: true) do |row|
      csv_data << row.to_h
    end
    csv_data
  end
end
