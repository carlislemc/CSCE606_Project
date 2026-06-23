# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CoursesController, type: :controller do
  before do
    session[:role] = "admin"
  end

  describe "POST #create" do
    let(:valid_attributes) do
      {
        course_name: "CSCE 607",
        course_number: "606",
        section: "500",
        instructor: "Dr. Richey",
        faculty_email: "rrrr@tamu.edu"
      }
    end
    let(:invalid_attributes) do
      { course_name: "", course_number: "" }
    end

    it "creates a new course and redirects to courses index" do
      expect {
        post :create, params: { course: valid_attributes }
      }.to change(Course, :count).by(1)

      expect(response).to redirect_to(courses_path)
      expect(flash[:notice]).to eq("Course was successfully created.")
    end
  end
  describe "PATCH #update" do
  let!(:course) { Course.create!(course_name: "CSCE 607", course_number: "606", section: "500", instructor: "Dr. Richey", faculty_email: "rrrr@tamu.edu") }
    let(:valid_attributes) do
      {
        instructor: "Ayush Gautamy"
      }
    end

    it "updates a course" do
      patch :update, params: { id: course.id, course: valid_attributes }
      course.reload
      expect(course.instructor).to eq("Ayush Gautamy")
      expect(flash[:notice]).to eq("Course was successfully updated.")
    end
  end

  describe "DELETE #destroy" do
    let!(:course) { Course.create!(course_name: "CSCE 607", course_number: "606", section: "500", instructor: "Dr. Richey", faculty_email: "rrrr@tamu.edu") }
    it "deletes the course and redirects to index" do
      expect {
        delete :destroy, params: { id: course.id }
      }.to change(Course, :count).by(-1)

      expect(response).to redirect_to(courses_path)
      expect(flash[:notice]).to eq("Course was successfully deleted.")
    end
  end

  describe "DELETE #clear" do
    let!(:course1) { Course.create!(course_name: "CSCE 607", course_number: "606", section: "500", instructor: "Dr. Richey", faculty_email: "rrrr@tamu.edu") }
    let!(:course2) { Course.create!(course_name: "CSCE 607", course_number: "606", section: "501", instructor: "Dr.richey", faculty_email: "rrrcr@tamu.edu") }
    it "deletes the course and redirects to index" do
      expect {
        delete :clear
      }.to change(Course, :count).to(0)

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("All courses have been deleted.")
    end
  end

  describe "course identity uniqueness" do
    it "rejects duplicate course_number and section even with whitespace differences" do
      Course.create!(course_name: "CSCE 607", course_number: "606", section: "500", instructor: "Dr. Richey", faculty_email: "rrrr@tamu.edu")

      duplicate = Course.new(
        course_name: "CSCE 607 Duplicate",
        course_number: " 606 ",
        section: "500 ",
        instructor: "Dr. Other",
        faculty_email: "other@tamu.edu"
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:course_number]).to include("has already been taken")
    end
  end

  describe "DELETE #destroy exact matching" do
    let!(:target_course) do
      Course.create!(course_name: "INTRO TO COMPUTER SYSTEM", course_number: "313/313H", section: "200-502", instructor: "A", faculty_email: "a@tamu.edu")
    end
    let!(:other_course) do
      Course.create!(course_name: "INTRO TO COMPUTER SYSTEM", course_number: "313", section: "200", instructor: "B", faculty_email: "b@tamu.edu")
    end
    let!(:target_match) do
      TaMatch.create!(course_number: "313/313H", section: "200-502", uin: "111111111")
    end
    let!(:other_match) do
      TaMatch.create!(course_number: "313", section: "200", uin: "222222222")
    end

    it "removes only matches tied to the deleted course identity" do
      expect do
        delete :destroy, params: { id: target_course.id }
      end.to change(Course, :count).by(-1)

      expect(TaMatch.exists?(target_match.id)).to be(false)
      expect(TaMatch.exists?(other_match.id)).to be(true)
      expect(Course.exists?(other_course.id)).to be(true)
    end
  end

  describe "GET #search_recs" do
  let!(:course1) { Course.create!(course_name: "CSCE 607", course_number: "606", section: "500", instructor: "Dr. Richey", faculty_email: "rrrr@tamu.edu") }
  let!(:course2) { Course.create!(course_name: "CSCE 617", course_number: "702", section: "500", instructor: "Dr.richey", faculty_email: "rrrcr@tamu.edu") }

    it "returns matching courses in JSON format" do
      get :search_recs, params: { term: "60" }, format: :json
      parsed = JSON.parse(response.body)

      expect(response).to be_successful
      expect(parsed.length).to eq(1)
      expect(parsed[0]).to include("id", "text", "course_number", "section")
      expect(parsed[0]["text"]).to include(parsed[0]["course_number"])
    end

    it "returns an empty array if no match" do
      get :search_recs, params: { term: "999" }, format: :json
      parsed = JSON.parse(response.body)
      expect(parsed).to eq([])
    end
  end
  describe "#generate_csv" do
  controller = CoursesController.new

  let!(:course1) { Course.create!(course_name: "CSCE 607", course_number: "606", section: "500", instructor: "Dr. Richey", faculty_email: "rrrr@tamu.edu", ta: 1, senior_grader: 2, grader: 3, pre_reqs: "") }
  let!(:course2) { Course.create!(course_name: "CSCE 617", course_number: "702", section: "500", instructor: "Dr.richey", faculty_email: "rrrcr@tamu.edu", ta: 1, senior_grader: 2, grader: 3, pre_reqs: "") }


  it "generates CSV with correct headers and values" do
    csv_output = controller.send(:generate_csv, [ course1, course2 ])
    csv_lines = CSV.parse(csv_output)

    # Check headers
    expect(csv_lines[0]).to eq([
      "Course Name", "Course Number", "Section", "Instructor", "Faculty Email", "TA", "Senior Grader", "Grader", "Pre-requisites"
    ])

    # Check content rows
    expect(csv_lines[1]).to eq([
      course1.course_name, course1.course_number, course1.section, course1.instructor,
      course1.faculty_email, "#{course1.ta}", "#{course1.senior_grader}", "#{course1.grader}", course1.pre_reqs
    ])

    expect(csv_lines[2]).to eq([
      course2.course_name, course2.course_number, course2.section, course2.instructor,
      course2.faculty_email, "#{course2.ta}", "#{course2.senior_grader}", "#{course2.grader}", course2.pre_reqs
    ])
  end
end
end
