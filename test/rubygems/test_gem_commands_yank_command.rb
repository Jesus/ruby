# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/yank_command'

class TestGemCommandsYankCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::YankCommand.new
    @cmd.options[:host] = 'http://example'

    @fetcher = Gem::RemoteFetcher.fetcher

    Gem.configuration.rubygems_api_key = 'key'
    Gem.configuration.api_keys[:KEY] = 'other'
  end

  def test_handle_options
    @cmd.handle_options %w[a --version 1.0 --platform x86-darwin -k KEY --host HOST]

    assert_equal %w[a],        @cmd.options[:args]
    assert_equal :KEY,         @cmd.options[:key]
    assert_equal "HOST",       @cmd.options[:host]
    assert_nil                 @cmd.options[:platform]
    assert_equal req('= 1.0'), @cmd.options[:version]
  end

  def test_handle_options_missing_argument
    %w[-v --version -p --platform].each do |option|
      assert_raises OptionParser::MissingArgument do
        @cmd.handle_options %W[a #{option}]
      end
    end
  end

  def test_execute
    yank_uri = 'http://example/api/v1/gems/yank'
    @fetcher.data[yank_uri] = ['Successfully yanked', 200, 'OK']

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req('= 1.0')

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%Yanking gem from http://example%, @ui.output
    assert_match %r%Successfully yanked%,      @ui.output


    platform = Gem.platforms[1]
    body = @fetcher.last_request.body.split('&').sort
    assert_equal %W[gem_name=a platform=#{platform} version=1.0], body

    assert_equal 'key', @fetcher.last_request['Authorization']

    assert_equal [yank_uri], @fetcher.paths
  end

  def test_execute_with_otp_success
    response_fail = 'You have enabled multifactor authentication but your request doesn\'t have the correct OTP code. Please check it and retry.'
    yank_uri = 'http://example/api/v1/gems/yank'
    @fetcher.data[yank_uri] = [
      [response_fail, 401, 'Unauthorized'],
      ['Successfully yanked', 200, 'OK']
    ]

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req('= 1.0')

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.execute
    end

    assert_match 'You have enabled multi-factor authentication. Please enter OTP code.', @otp_ui.output
    assert_match 'Code: ', @otp_ui.output
    assert_match %r%Yanking gem from http://example%, @otp_ui.output
    assert_match %r%Successfully yanked%,      @otp_ui.output
    assert_equal '111111', @fetcher.last_request['OTP']
  end

  def test_execute_with_otp_failure
    response = 'You have enabled multifactor authentication but your request doesn\'t have the correct OTP code. Please check it and retry.'
    yank_uri = 'http://example/api/v1/gems/yank'
    @fetcher.data[yank_uri] = [response, 401, 'Unauthorized']

    @cmd.options[:args]           = %w[a]
    @cmd.options[:added_platform] = true
    @cmd.options[:version]        = req('= 1.0')

    @otp_ui = Gem::MockGemUi.new "111111\n"
    use_ui @otp_ui do
      @cmd.execute
    end

    assert_match 'You have enabled multi-factor authentication. Please enter OTP code.', @otp_ui.output
    assert_match response, @otp_ui.output
    assert_match 'Code: ', @otp_ui.output
    assert_equal '111111', @fetcher.last_request['OTP']
  end

  def test_execute_key
    yank_uri = 'http://example/api/v1/gems/yank'
    @fetcher.data[yank_uri] = ['Successfully yanked', 200, 'OK']

    @cmd.options[:args]    = %w[a]
    @cmd.options[:version] = req('= 1.0')
    @cmd.options[:key]     = :KEY

    use_ui @ui do
      @cmd.execute
    end

    body = @fetcher.last_request.body.split('&').sort
    assert_equal %w[gem_name=a version=1.0], body
    assert_equal 'other', @fetcher.last_request['Authorization']
  end

  def test_execute_host
    host = 'https://other.example'
    yank_uri = "#{host}/api/v1/gems/yank"
    @fetcher.data[yank_uri] = ['Successfully yanked', 200, 'OK']

    @cmd.options[:args]    = %w[a]
    @cmd.options[:version] = req('= 1.0')
    @cmd.options[:host]    = host

    use_ui @ui do
      @cmd.execute
    end

    assert_match %r%Yanking gem from https://other.example%, @ui.output
    assert_match %r%Successfully yanked%,      @ui.output

    body = @fetcher.last_request.body.split('&').sort
    assert_equal %w[gem_name=a version=1.0], body
    assert_equal 'key', @fetcher.last_request['Authorization']
    assert_equal [yank_uri], @fetcher.paths
  end

end
