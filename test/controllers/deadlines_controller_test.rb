require "test_helper"

class DeadlinesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @deadline = @user.family.deadlines.create!(name: "ITV coche", kind: "itv", due_on: Date.current + 10.days, repeat_months: 12)
  end

  test "lists the deadlines" do
    get deadlines_path

    assert_response :ok
    assert_select "a[href='#{edit_deadline_path(@deadline)}']"
  end

  test "new suggests the ITV for a vehicle" do
    get new_deadline_path(account_id: accounts(:vehicle).id)

    assert_response :ok
    assert_select "select[name='deadline[kind]'] option[selected][value='itv']"
  end

  test "creates one" do
    assert_difference -> { @user.family.deadlines.count }, 1 do
      post deadlines_path, params: { deadline: { name: "Garantía portátil", kind: "warranty", due_on: "2028-03-01", remind_days: 30, repeat_months: "" } }
    end

    assert_redirected_to deadlines_path
    assert_nil @user.family.deadlines.find_by(name: "Garantía portátil").repeat_months
  end

  test "rejects one without a date" do
    assert_no_difference -> { Deadline.count } do
      post deadlines_path, params: { deadline: { name: "Sin fecha", kind: "other", due_on: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "updates and deletes" do
    patch deadline_path(@deadline), params: { deadline: { name: "ITV Ateca" } }
    assert_equal "ITV Ateca", @deadline.reload.name

    assert_difference -> { Deadline.count }, -1 do
      delete deadline_path(@deadline)
    end
  end

  test "marking a repeating one done moves it a year on" do
    due = @deadline.due_on

    patch complete_deadline_path(@deadline)

    assert_equal due.advance(years: 1), @deadline.reload.due_on
  end

  test "Inicio shows what is coming up" do
    get root_path

    assert_response :ok
    assert_select "a[href='#{deadlines_path}']"
  end

  test "another family's deadline is not found" do
    other = families(:empty).deadlines.create!(name: "Ajena", kind: "other", due_on: Date.current)

    patch complete_deadline_path(other)

    assert_response :not_found
  end
end
