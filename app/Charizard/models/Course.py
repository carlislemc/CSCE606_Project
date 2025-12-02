from __future__ import annotations

import math
import re

from models.Professor import FeedbackType
from typing import List

from models.DataModel import DataModel


class Course(DataModel):
    class DataFormat:
        COURSE_NUM_REGEX = "\\d{3,4}"  # Matches 3 or 4 digit numbers
        COURSE_NUM_RANGE_REGEX = "\\d{3,4}(?:-[0-9a-zA-Z]{1,4})?"  # Matches '500-GV', '500-503', '500', '5001', '5001-GV', etc
        COURSE_NAME = "Course_Name"
        COURSE_NUMS = "Course_Number"
        SECTION_IDS = "Section"
        INSTRUCTOR = "Instructor"
        FACT_EMAIL = "Faculty_Email"
        NUM_TA_NEEDED = "TA"
        NUM_SNR_GRADER_NEEDED = "Senior_Grader"
        NUM_GRADER_NEEDED = "Grader"
        PROF_PRE_REQS = "Professor Pre-Reqs"

        COLUMNS = [
            COURSE_NAME,
            COURSE_NUMS,
            SECTION_IDS,
            INSTRUCTOR,
            FACT_EMAIL,
            NUM_TA_NEEDED,
            NUM_SNR_GRADER_NEEDED,
            NUM_GRADER_NEEDED,
            PROF_PRE_REQS,
        ]

    def __init__(self, course_name, course_numbers, is_writing_or_comm_course, section_ids, instructor, faculty_email,
                 tas_needed, senior_grader_needed, graders_needed,
                 ta_priority_list=None, ta_deny_list=None, preferred_prerequisites=None):
        self.course_name: str = course_name
        self.course_numbers: List[str] = course_numbers
        self.is_writing_or_comm_course: bool = is_writing_or_comm_course
        self.section_ids: List[str] = section_ids
        self.instructor: str = instructor
        self.faculty_email: str = faculty_email
        self.tas_needed: int = tas_needed
        self.senior_grader_needed: int = senior_grader_needed
        self.graders_needed: int = graders_needed
        self.ta_priority_list: List[str] = ta_priority_list if ta_priority_list else []
        self.ta_deny_list: List[str] = ta_deny_list if ta_deny_list else []
        self.preferred_prerequisites: List[str] = preferred_prerequisites if preferred_prerequisites else []

    def __eq__(self, other: Course):  # pragma: no cover
        if type(other) != type(self):
            return False
        return \
            self.course_name == other.course_name and \
            self.course_numbers == other.course_numbers and \
            self.section_ids == other.section_ids and \
            self.instructor == other.instructor and \
            self.faculty_email == other.faculty_email and \
            self.tas_needed == other.tas_needed and \
            self.senior_grader_needed == other.senior_grader_needed and \
            self.graders_needed == other.graders_needed and \
            self.ta_priority_list == other.ta_priority_list and \
            self.ta_deny_list == other.ta_deny_list and \
            self.preferred_prerequisites == other.preferred_prerequisites

    def __str__(self) -> str:  # pragma: no cover
        return f'{self.course_name=},' \
               f'{self.course_numbers=},' \
               f'{self.section_ids=},' \
               f'{self.instructor=},' \
               f'{self.faculty_email=},' \
               f'{self.tas_needed=},' \
               f'{self.senior_grader_needed=},' \
               f'{self.graders_needed=},' \
               f'{self.ta_priority_list=},' \
               f'{self.ta_deny_list=},' \
               f'{self.preferred_prerequisites=}'

    @classmethod
    def get_empty_model(cls) -> Course:
        return Course(
            course_name='',
            course_numbers=[],
            is_writing_or_comm_course=False,
            section_ids=[],
            instructor='',
            faculty_email='',
            tas_needed=0,
            senior_grader_needed=0,
            graders_needed=0,
            ta_priority_list=[],
            ta_deny_list=[],
            preferred_prerequisites=[],
        )

    def set_by_column(self, field_title: str, value):
        if field_title == self.DataFormat.COURSE_NAME:
            self.course_name = value.strip()
        elif field_title == self.DataFormat.COURSE_NUMS:
            self.course_numbers = re.findall(self.DataFormat.COURSE_NUM_REGEX, value)
            self.is_writing_or_comm_course = 'W' in value or 'C' in value
        elif field_title == self.DataFormat.SECTION_IDS:
            self.section_ids = re.findall(self.DataFormat.COURSE_NUM_RANGE_REGEX, value)
        elif field_title == self.DataFormat.INSTRUCTOR:
            self.instructor = value.strip()
        elif field_title == self.DataFormat.FACT_EMAIL:
            self.faculty_email = value.lower().strip()
        elif field_title == self.DataFormat.NUM_TA_NEEDED:
            # we round up 0.5 TAs
            self.tas_needed = math.ceil(value)
        elif field_title == self.DataFormat.NUM_SNR_GRADER_NEEDED:
            self.senior_grader_needed = int(value)
        elif field_title == self.DataFormat.NUM_GRADER_NEEDED:
            self.graders_needed = int(value)
        elif field_title == self.DataFormat.PROF_PRE_REQS:
            self.preferred_prerequisites = re.findall(self.DataFormat.COURSE_NUM_REGEX, value)

    @classmethod
    def augment_courses_with_prefs(cls, courses, preferences):
        for preference in preferences:
            for course in courses:
                if preference.professor_email == course.faculty_email and \
                        preference.selected_course in course.course_numbers:
                    if preference.student_feedback == FeedbackType.WANT_TO_WORK_WITH_STUDENT:
                        course.ta_priority_list.append(preference.selected_student_email)
                    elif preference.student_feedback == FeedbackType.DO_NOT_WANT_TO_WORK_WITH_STUDENT:
                        course.ta_deny_list.append(preference.selected_student_email)
