# frozen_string_literal: true

class Applicant < ApplicationRecord
  belongs_to :user, foreign_key: "confirm", optional: true
  before_validation :ensure_timestamp
  before_save :normalize_courses

  validates :confirm, uniqueness: true
  has_many :recommendations

  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :degree, presence: true
  validates :positions, presence: true
  validates :number, presence: true, format: { with: /\A\+?[0-9\-]{10,15}\z/, message: "must be a valid phone number" }
  validates :uin, presence: true,format: {
              with: /\A\d{9}\z/,
              message: "must be exactly 9 digits"
            }
  validates :hours, presence: true, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 16.0 }
  validates :citizenship, presence: true
  validates :cert, presence: true
  validates :gpa, presence: true, numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 4.0 }
  validate :min_course_choice
  validate :check_duplicates
  validates :prev_course, length: { maximum: 200, too_long: "%{count} characters is the maximum allowed" },
            format: { 
              with: /\A\s*(\d{3}\s*,\s*)*\d{3}?\s*,?\s*\z/,
              message: "Must Only Include Course Numbers\ '123,345,456'",
              allow_blank: true
            }
  validates :prev_uni, length: { maximum: 200, too_long: "%{count} characters is the maximum allowed" },
            format: { 
              with: /\A\s*(\d{3}\s*,\s*)*\d{3}?\s*,?\s*\z/,
              message: "Must Only Include Course Numbers Numbers\ '123,345,456'",
              allow_blank: true
            }
  validates :prev_ta, length: { maximum: 200, too_long: "%{count} characters is the maximum allowed" },
            format: { 
              with: /\A\s*(\d{3}\s*,\s*)*\d{3}?\s*,?\s*\z/,
              message: "Must Only Include Course Numbers Numbers\ '123,345,456'",
              allow_blank: true
            }

  validates :advisor, presence: true, if: :requires_advisor?

  # type casting
  ransacker :uin do |parent|
    Arel.sql("CAST(#{parent.table.name}.uin AS TEXT)")
  end

  def self.ransackable_attributes(auth_object = nil)
    super + [ "name", "email", "uin_text", "degree", "course_choices" ]
  end

  def uin_text
    uin.to_s
  end


  ransacker :uin_text do
    Arel.sql("CAST(uin AS TEXT)")
  end

  ransacker :course_choices do
    Arel.sql("CAST(choice_1 AS TEXT) || ',' || CAST(choice_2 AS TEXT) || ',' || CAST(choice_3 AS TEXT) || ',' || " +
             "CAST(choice_4 AS TEXT) || ',' || CAST(choice_5 AS TEXT) || ',' || CAST(choice_6 AS TEXT) || ',' || " +
             "CAST(choice_7 AS TEXT) || ',' || CAST(choice_8 AS TEXT) || ',' || CAST(choice_9 AS TEXT) || ',' || " +
             "CAST(choice_10 AS TEXT)")
  end



  def self.ransackable_associations(auth_object = nil)
    []
  end

  ransacker :course_choices do
    Arel.sql("CAST(choice_1 AS TEXT) || ',' || CAST(choice_2 AS TEXT) || ',' || CAST(choice_3 AS TEXT) || ',' || " +
             "CAST(choice_4 AS TEXT) || ',' || CAST(choice_5 AS TEXT) || ',' || CAST(choice_6 AS TEXT) || ',' || " +
             "CAST(choice_7 AS TEXT) || ',' || CAST(choice_8 AS TEXT) || ',' || CAST(choice_9 AS TEXT) || ',' || " +
             "CAST(choice_10 AS TEXT)")
  end

  def requires_advisor?
    degree.to_s.strip.casecmp("phd").zero?
  end

  def normalize_courses
    [:prev_uni, :prev_course, :prev_ta].each do |field|
      value = self.send(field)
      if value.present?
        cleaned = value.gsub(/\s+/, '')
                      .sub(/,+\z/, '')
        self.send("#{field}=", cleaned)
      end
    end
  end
  
  def blacklisted?
    Blacklist.exists?(["LOWER(student_email) = ? OR LOWER(student_name) = ?", email.to_s.downcase, name.to_s.downcase])
  end

  def check_duplicates
    %i[prev_course prev_ta prev_uni].each do |field|
      value = send(field)
      if value.present?
        numbers = value.gsub(/\s+/, '').split(',')
        if numbers.uniq.length != numbers.length
          errors.add(field, "must not contain duplicate course numbers")
        end
      end
    end
  end

  private
  def ensure_timestamp
    self.timestamp ||= Time.current
  end

  def min_course_choice
    course_choices = [
        choice_1, choice_2, choice_3, choice_4, choice_5,
        choice_6, choice_7, choice_8, choice_9, choice_10
    ]

    if course_choices.all?(&:blank?)
      errors.add(:base, "You must select at least one Course Choice.")
    end
  end
end
