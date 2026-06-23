# frozen_string_literal: true

module NewNeedsSync
  extend ActiveSupport::Concern
  require "csv"

  private

  def rebuild_new_needs_csv
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
end