Feature: Applicant Search by Name or Email
  In order to quickly find an applicant
  As a user
  I want to search applicants by Name or Email

  Background:
    Given I am logged in as a TAMU user
    And the following applicant records exist:
      | name         | email             | uin | degree    | positions  | number | hours | citizenship | cert      |
      | Alice Smith  | alice@example.com | 111 | Master's  | Developer  | 1      | 40    | US          | Certified |
      | Bob Johnson  | bob@example.com   | 222 | PhD       | Researcher | 2      | 30    | US          | Certified |
      | Carol Brown  | carol@example.com | 333 | PhD       | Analyst    | 3      | 35    | US          | Certified |

  Scenario: Search by Name
    When I navigate to the applicant search page
    And I enter "Alice" into the "Search for Applicant" field
    And I click the "Search" button
    Then I should see the applicant "Alice Smith"
    And I should not see the applicant "Bob Johnson"
    And I should not see the applicant "Carol Brown"

  Scenario: Search by Email
    When I navigate to the applicant search page
    And I enter "bob@example.com" into the "Search for Applicant" field
    And I click the "Search" button
    Then I should see "Showing 1 applicant"
    Then I should see the applicant "Bob Johnson"
    And I should not see the applicant "Alice Smith"
    And I should not see the applicant "Carol Brown"

  Scenario: Search with no matches
    When I navigate to the applicant search page
    And I enter "missing@example.com" into the "Search for Applicant" field
    And I click the "Search" button
    Then I should see "Showing 0 applicants"
    And I should not see the applicant "Alice Smith"
    And I should not see the applicant "Bob Johnson"
    And I should not see the applicant "Carol Brown"
