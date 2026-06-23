# frozen_string_literal: true

class Course < ApplicationRecord
  before_validation :normalize_identity_fields

  validates :course_name, :course_number, :section, :instructor, presence: true
  validates :course_number, uniqueness: { scope: :section, case_sensitive: false }
  validates :faculty_email, uniqueness: false, format: { with: URI::MailTo::EMAIL_REGEXP }

  def normalize_identity_fields
    self.course_number = course_number.to_s.strip
    self.section = section.to_s.strip
  end

  def self.ransackable_attributes(auth_object = nil)
    super + [ "course_name", "course_number", "section", "instructor" ]
  end
  def self.ransackable_associations(auth_object = nil)
    []
  end
end
