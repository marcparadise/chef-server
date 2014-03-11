require 'spec_helper'

describe User do

  before do
    @user = User.new
  end

  subject { @user }

  it { should respond_to(:username) }
  it { should respond_to(:password) }
  it { should respond_to(:first_name) }
  it { should respond_to(:last_name) }
  it { should respond_to(:email) }
  it { should respond_to(:public_key) }
  it { should respond_to(:authenticate) }

end