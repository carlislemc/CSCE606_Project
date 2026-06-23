# frozen_string_literal: true

class AddUniqueIndexToCoursesCourseNumberSection < ActiveRecord::Migration[7.2]
  class Course < ApplicationRecord
    self.table_name = "courses"
  end

  def up
    deduplicate_courses
    add_index :courses, [:course_number, :section], unique: true, name: "index_courses_on_course_number_and_section"
  end

  def down
    remove_index :courses, name: "index_courses_on_course_number_and_section"
  end

  private

  def deduplicate_courses
    keepers = {}
    duplicate_ids = []

    Course.order(:id).find_each do |course|
      course_number = course.course_number.to_s.strip.downcase
      section = course.section.to_s.strip.downcase
      key = [course_number, section]

      if keepers[key]
        duplicate_ids << course.id
      else
        keepers[key] = course.id
        course.update_columns(course_number: course.course_number.to_s.strip, section: course.section.to_s.strip)
      end
    end

    Course.where(id: duplicate_ids).delete_all if duplicate_ids.any?
  end
end