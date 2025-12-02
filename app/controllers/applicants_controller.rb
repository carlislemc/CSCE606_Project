# frozen_string_literal: true

# Used to manage the applicants
class ApplicantsController < ApplicationController
  before_action :set_applicant, only: %i[ show edit update destroy ]
  skip_before_action :require_login, if: -> { Rails.env.test? }

  before_action :authorize_admin_or_faculty!, only: [:index, :wipe_applicants, :search, :search_email, :search_uin]
  before_action :authorize_owner_or_admin_or_faculty!, only: %i[show edit update destroy]

  



  # GET /applicants or /applicants.json
  def index
    @q = Applicant.ransack(params[:q] || {})

    # Sort fallback
    permitted_columns = Applicant.column_names
    sort_column = permitted_columns.include?(params[:sort]) ? params[:sort] : "name"
    sort_direction = params[:direction] == "desc" ? "desc" : "asc"

    @applicants = @q.result(distinct: true).order("#{sort_column} #{sort_direction}")
    @total_jobs = Course.sum(:ta) + Course.sum(:senior_grader) + Course.sum(:grader)
    @total_jobs = @total_jobs.to_i

    @changes = !TaMatch.exists? && !SeniorGraderMatch.exists? && !GraderMatch.exists?

  end

  # Search for applicants by name
  def search
    term = params[:term].to_s.strip.downcase
    applicants = if term.present?
                   Applicant.where("LOWER(name) LIKE ?", "%#{term}%").limit(10)
    else
                   Applicant.limit(10)
    end

    render json: applicants.map { |applicant| {
      id: applicant.id,
      text: "#{applicant.name} (#{applicant.email})",
      name: applicant.name,
      email: applicant.email,
      degree: applicant.degree,
      uin: applicant.uin,
      number: applicant.number,
      citizenship: applicant.citizenship,
      hours: applicant.hours,
      prev_ta: applicant.prev_ta,
      cert: applicant.cert
    } }
  end

  # Search for applicants by email
  def search_email
    applicants = Applicant.where("email LIKE ?", "%#{params[:term]}%").limit(10)
    render json: applicants.map { |applicant| {
      id: applicant.id,
      text: "#{applicant.name} (#{applicant.email})",
      name: applicant.name,
      email: applicant.email,
      degree: applicant.degree,
      uin: applicant.uin,
      number: applicant.number,
      citizenship: applicant.citizenship,
      hours: applicant.hours,
      prev_ta: applicant.prev_ta,
      cert: applicant.cert } }
  end

  # Search for applicants by UIN
  def search_uin
    applicants = Applicant.where("uin LIKE ?", "%#{params[:term]}%").limit(10)
    render json: applicants.map { |applicant| {
      id: applicant.id,
      text: "#{applicant.name} (#{applicant.email})",
      name: applicant.name,
      email: applicant.email,
      degree: applicant.degree,
      uin: applicant.uin,
      number: applicant.number,
      citizenship: applicant.citizenship,
      hours: applicant.hours,
      prev_ta: applicant.prev_ta,
      cert: applicant.cert } }
  end

  # GET /applicants/1 or /applicants/1.json
  def show
  end

  def toggle_blacklist
    @applicant = Applicant.find(params[:id])
    if @applicant.blacklisted?
      # Remove from blacklist
      Blacklist.where("LOWER(student_email) = ?", @applicant.email.downcase).destroy_all
    else
      # Add to blacklist
      Blacklist.create!(
        student_name: @applicant.name,
        student_email: @applicant.email
      )
    end
    redirect_back(fallback_location: applicants_path)
  end

  # GET /applicants/new
  def new
    if session[:user_id].present?
      # Check if the user has already submitted an application
      user = User.find(session[:user_id])
      if user.applicant
        redirect_to user.applicant
      else
        @applicant = Applicant.new
        @courses = Course.select(:course_number, :course_name).distinct.map { |c| ["#{c.course_number} - #{c.course_name}", c.course_number] }

      end
    else
      redirect_to root_path, alert: "Please log in to submit an application."
    end
  end




  # GET /applicants/1/edit
  def edit
    @applicant = Applicant.find(params[:id])
    @courses = Course.select(:course_number, :course_name).distinct.map { |c| ["#{c.course_number} - #{c.course_name}", c.course_number] }

  end

  # POST /applicants or /applicants.json
  def create
    if session[:user_id].present?
      user = User.find(session[:user_id])
      if user.applicant
        redirect_to user.applicant, alert: "You have already submitted an application."
        return
      end

      modified_params = applicant_params
      session_email = session[:email]
      session_user = session[:user]

      is_blacklisted = Blacklist.exists?(
        ["LOWER(student_email) = ?", session_email.to_s.downcase]
      )

      final_name = is_blacklisted ? "*#{session_user}" : session_user
       
      @applicant = Applicant.new(modified_params)
      @applicant.email = session_email
      @applicant.name = final_name
      @applicant.confirm = user.id

      respond_to do |format|
        if @applicant.save
          blacklist_entry = Blacklist.find_by(
            "LOWER(student_name) = ? AND LOWER(student_email) = ?",
            @applicant.name.downcase,
            @applicant.email.downcase
          )
          if TaMatch.exists? || SeniorGraderMatch.exists? || GraderMatch.exists?
            if !blacklist_entry.present? &&  !@applicant.name.strip.downcase.start_with?("*")
              # Backup the applicant to the unassigned applicants CSV and model
              UnassignedApplicant.create(@applicant.attributes.except("id", "created_at", "updated_at", "confirm"))
            end
          end
          format.html { redirect_to @applicant, notice: "Application submitted successfully." }
          format.json { render :show, status: :created, location: @applicant }
        else
          @courses = Course.select(:course_number, :course_name).distinct.map { |c| "#{c.course_number} - #{c.course_name}" }
          format.html { render :new, status: :unprocessable_entity }
          format.json { render json: @applicant.errors, status: :unprocessable_entity }
        end
      end
    else
      redirect_to root_path, alert: "Please log in to submit an application."
    end
  end

  # PATCH/PUT /applicants/1 or /applicants/1.json
  def update
    respond_to do |format|
      if @applicant.update(applicant_params)
        if UnassignedApplicant.exists?(email: @applicant.email)
          unassigned_applicant = UnassignedApplicant.find_by(email: @applicant.email)
          unassigned_applicant.update(applicant_params)
          unassigned_applicant.save
        end
        format.html { redirect_to @applicant, notice: "Applicant was successfully updated." }
        format.json { render :show, status: :ok, location: @applicant }
        flash[:notice] = "Applicant was successfully updated."
      else
        @courses = Course.select(:course_number, :course_name).distinct.map { |c| ["#{c.course_number} - #{c.course_name}", c.course_number] }
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @applicant.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /applicants/1 or /applicants/1.json
  def destroy
    @applicant.destroy!

    respond_to do |format|
      format.html {
        if session[:role].to_s == "admin"
          redirect_to applicants_path, notice: "Applicant was successfully destroyed."
        else
          redirect_to root_path, notice: "Applicant was successfully destroyed."
        end
       }
      format.json { head :no_content }
    end
  end
  # Delete all applicants
  def wipe_applicants
    Applicant.delete_all
    UnassignedApplicant.delete_all
    Recommendation.delete_all
    WithdrawalRequest.delete_all
    GraderMatch.delete_all
    SeniorGraderMatch.delete_all
    TaMatch.delete_all
    Dir[Rails.root.join("app/Charizard/util/public/output/*.csv")].each do |file|
      File.delete(file)
    end
    redirect_to root_path, notice: "All Applicants have been cleared."
  end

  # for view my application
  def my_application
    # this is a temporary value for debugging need to be fixed after login is finished
    @applicant = Applicant.find_by(email: session[:email])
    @changes = !TaMatch.exists? && !SeniorGraderMatch.exists? && !GraderMatch.exists?
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_applicant
      @applicant = Applicant.find(params[:id])
    end

    def authorize_admin_or_faculty!
      case session[:role].to_s
      when "admin", "faculty"
      else
        redirect_to root_path, alert: "Unauthorized access."
      end
    end

    
    
    def authorize_owner_or_admin_or_faculty!
      @applicant = Applicant.find(params[:id])
      if session[:role].to_s == "admin" or session[:role].to_s == "faculty"
        return
      elsif session[:user_id].present?
        user = User.find(session[:user_id])
        if user.applicant == @applicant
          return
        end
      end
      redirect_to root_path, alert: "Unauthorized access."
    end
  

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

    # Only allow a list of trusted parameters through.
    def applicant_params
      params.require(:applicant).permit(:email, :name, :degree, :positions, :gpa,
:number, :uin, :hours, :citizenship, :cert, :prev_course, :prev_uni, :prev_ta, :advisor, :choice_1, :choice_2, :choice_3, :choice_4, :choice_5, :choice_6, :choice_7, :choice_8, :choice_9, :choice_10)
    end
end
