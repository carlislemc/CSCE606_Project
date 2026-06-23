# frozen_string_literal: true

# This controller manages the Course functions of the application
class CoursesController < ApplicationController
  skip_before_action :require_login, if: -> { Rails.env.test? }
  before_action :authorize_admin!, only: [:index, :create, :update, :destroy, :import, :clear]
  require "csv"
  include NewNeedsSync

  # will sort the courses by the thier columns
  def index
    @q = Course.ransack(params[:q])
    sort_column = params[:sort] || "course_name"
    sort_direction = params[:direction] == "desc" ? "desc" : "asc"

    @courses = @q.result(distinct: true).order("#{sort_column} #{sort_direction}")
    @ta = Course.sum(:ta).to_i
    @senior_grader = Course.sum(:senior_grader).to_i
    @grader = Course.sum(:grader).to_i
    @total = @ta + @senior_grader + @grader

  end

  # Will search for courses based on params
  def search_recs
    courses = Course.where("LOWER(course_name) LIKE ? OR course_number LIKE ?", "%#{params[:term]}%", "%#{params[:term]}%").limit(10)
    render json: courses.map { |course| {
      id: course.id,
      text: "#{course.course_number} - #{course.section}",
      course_number: course.course_number,
      section: course.section,
      name: course.course_name
    }}
  end

  # Will search for courses. Used in the application form for students
  def search
    if params[:term].present?
      courses = Course.where("course_name LIKE ? OR course_number LIKE ?", "%#{params[:term]}%", "%#{params[:term]}%")
    else
      courses = Course.all
    end

    render json: courses.map { |c| { id: c.id, name: "#{c.course_number} - #{c.course_name} (Section: #{c.section})" } }
  end

  # Will create a new course
  def create
    @course = Course.new(course_params)
    respond_to do |format|
      if @course.save
        if TaMatch.count > 0 || GraderMatch.count > 0 || SeniorGraderMatch.count > 0
          rebuild_new_needs_csv
        end
        format.html { redirect_to courses_path, notice: "Course was successfully created." }
        format.json { render :show, status: :created, location: @course }
        format.js
      else
        Rails.logger.debug "Course failed to save: #{@course.errors.full_messages}"
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @course.errors, status: :unprocessable_entity }
        format.js
      end
    end
  end

  # Used to update a course
  def update
    # Rails.logger.debug "CSRF Token: #{form_authenticity_token}"
    # Rails.logger.debug "Received Headers: #{request.headers.to_h}"
    # Rails.logger.debug "Params: #{params.inspect}"
    @course = Course.find(params[:id])

    respond_to do |format|
      if @course.update(course_params)
        format.html { redirect_to courses_path, notice: "Course was successfully updated." }
        format.json { render json: { message: "Course updated successfully", id: @course.id }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @course.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # Will delete a course
  def destroy
    @course = Course.find(params[:id])
    delete_matches_for_course(TaMatch, @course)
    delete_matches_for_course(GraderMatch, @course)
    delete_matches_for_course(SeniorGraderMatch, @course)

    @course.destroy
    rebuild_new_needs_csv if File.exist?(Rails.root.join("app", "Charizard", "util", "public", "output", "New_Needs.csv"))
    respond_to do |format|
      format.js
      format.html { redirect_to courses_path, notice: "Course was successfully deleted." }
    end
  end
  # Will import a CSV file that will create courses base on the Headers
  # Course_Name, Course_Number, Section, Instructor, Faculty_Email, TA, Senior_Grader, Grader, Professor Pre-Reqs
  def import
    file = params[:csv_file]

    if file.nil?
      redirect_to courses_path, alert: "No file selected"
      return
    end
    begin  
      csv_data = CSV.read(file.path, headers: true)
      normalize_headers = csv_data.headers.map { |h| h.strip.downcase }
      # Process each row, cleaning up the values as well
      csv_data.each do |row|
        row = row.to_h.transform_keys { |key| key.strip.downcase }.transform_values { |value| value.strip if value.respond_to?(:strip) }
        # Upsert by identity so repeated imports do not create duplicate classes.
        ta_value = row["ta?"] || row["ta"]
        course_attrs = {
          course_name: row["course_name"],
          course_number: row["course_number"],
          section: row["section"],
          instructor: row["instructor"],
          faculty_email: row["faculty_email"],
          ta: ta_value.to_f,
          senior_grader: row["senior_grader"].to_f,
          grader: row["grader"].to_f,
          pre_reqs: row["professor pre_reqs"]
        }
        upsert_course(course_attrs)
      end
      redirect_to courses_path, notice: "Courses imported successfully!"
    rescue StandardError => e
      Rails.logger.error "Error importing CSV: #{e.message}"
      Rails.logger.error "Check Headers: #{csv_data.headers.inspect}"
      session[:notice] = "Error importing file: #{e.message}, Check headers for proper capitalization and whitespace"
      redirect_to courses_path, notice: "Error importing CSV: Check headers for proper capitalization and whitespace"
    end
  end

  # Will clear all the courses in the database
  def clear
    Course.delete_all
    if request
      redirect_to root_path, notice: "All courses have been deleted."
    else
      puts "All courses have been deleted."
    end
  end

  def add_to_modified_assignments(model_record)
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

  def backup_unassigned_applicant(uin)
    applicant = Applicant.find_by(uin: uin)
    return unless applicant

    UnassignedApplicant.create(applicant.attributes.except("id", "created_at", "updated_at", "confirm"))
  end

  def upsert_course(attrs)
    identity = {
      course_number: attrs[:course_number].to_s.strip,
      section: attrs[:section].to_s.strip
    }

    course = Course.find_or_initialize_by(identity)
    course.assign_attributes(attrs)
    course.save!
  end

  def delete_matches_for_course(model_class, course)
    target_course_number = course.course_number.to_s.strip.downcase
    target_section = course.section.to_s.strip.downcase

    model_class.find_each do |match|
      next unless match.course_number.to_s.strip.downcase == target_course_number &&
                  match.section.to_s.strip.downcase == target_section

      add_to_modified_assignments(match)
      backup_unassigned_applicant(match.uin)
      match.destroy
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

  # Requires course params for creation
  def course_params
    params.require(:course).permit(:course_name, :course_number, :section, :instructor, :faculty_email,
                                   :ta, :senior_grader, :grader, :pre_reqs)
  end
end
