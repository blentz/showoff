require 'spec_helper'
require 'commandline_parser'

RSpec.describe CommandlineParser do
  let(:parser) { described_class.new }

  it 'parses a single command with output' do
    input = "$ echo hi\nhello world\n"
    tree = parser.parse(input)
    # Expect one command node
    expect(tree.size).to eq(1)
    cmd = tree.first[:command]
    expect(cmd[:prompt].to_s).to eq('$')
    expect(cmd[:input].to_s).to eq('echo hi')
    expect(cmd[:output].to_s).to include('hello world')
  end

  it 'parses multiple commands with different prompts' do
    input = "# id\nuid=0(root) gid=0(root)\n>> quit\nbye\n"
    tree = parser.parse(input)
    expect(tree.size).to eq(2)
    expect(tree[0][:command][:prompt].to_s).to eq('#')
    expect(tree[1][:command][:prompt].to_s).to eq('>>')
  end

  it 'parses multiline input lines ending with backslashes' do
    # Parser preserves backslash-newlines in input for display purposes
    # The continuation characters are kept so presentations can show
    # how to type multi-line shell commands
    input = <<~TXT
      $ echo one \\
      two \\
      three
      ok
    TXT
    tree = parser.parse(input)
    cmd = tree.first[:command]
    # Input preserves the backslash-newline sequences
    expect(cmd[:input].to_s).to include('echo one')
    expect(cmd[:input].to_s).to include('\\')
    expect(cmd[:output].to_s).to include('ok')
  end

  it 'handles optional output blocks and blank lines' do
    input = <<~TXT
      $ date


      Tue Dec 25 12:00:00 UTC 2025
    TXT
    tree = parser.parse(input)
    cmd = tree.first[:command]
    expect(cmd[:input].to_s).to eq('date')
    expect(cmd[:output].to_s).to include('Tue Dec')
  end
end
