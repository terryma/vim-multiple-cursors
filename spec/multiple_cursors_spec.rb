require 'spec_helper'

def set_file_content(string)
  string = normalize_string_indent(string)
  File.open(filename, 'w'){ |f| f.write(string) }
  vim.edit filename
end

def get_file_content()
  vim.write
  IO.read(filename).strip
end

def before(string)
  set_file_content(string)
end

def after(string)
  get_file_content().should eq normalize_string_indent(string)
end

def type(string)
  string.scan(/<.*?>|./).each do |key|
    if /<.*>/.match(key)
      vim.feedkeys "\\#{key}"
    else
      vim.feedkeys key
    end
  end
end

describe "Multiple Cursors" do
  let(:filename) { 'test.txt' }

  specify "#multiline replacement" do
    before <<-EOF
      hello
      hello
      hello
    EOF

    type '<C-n><C-n><C-n>cworld<Esc>'

    after <<-EOF
      world
      world
      world
    EOF
  end

  specify "#single line replacement" do
    before <<-EOF
      hello hello hello
    EOF

    type '<C-n><C-n><C-n>cworld<Esc>'

    after <<-EOF
      world world world
    EOF
  end

  specify "#mixed line replacement" do
    before <<-EOF
      hello hello
      hello
    EOF

    type '<C-n><C-n><C-n>cworld<Esc>'

    after <<-EOF
      world world
      world
    EOF
  end

  specify "#new line in insert mode" do
    before <<-EOF
      hello
      hello
    EOF

    type '<C-n><C-n>chello<CR>world<Esc>'

    after <<-EOF
      hello
      world
      hello
      world
    EOF
  end

  specify "#normal mode 'o'" do
    before <<-EOF
      hello
      hello
    EOF

    type '<C-n><C-n>voworld<Esc>'

    after <<-EOF
      hello
      world
      hello
      world
    EOF
  end

  specify "#normal mode 'O'" do
    before <<-EOF
      hello
      hello
    EOF

    type '<C-n><C-n>vOworld<Esc>'

    after <<-EOF
      world
      hello
      world
      hello
    EOF
  end

  specify "#find command basic" do
    before <<-EOF
      hello
      hello
    EOF

    vim.normal ':MultipleCursorsFind hello<CR>'
    type 'cworld<Esc>'

    after <<-EOF
      world
      world
    EOF
  end

  specify "#visual line mode replacement" do
    before <<-EOF
      hello world
      hello world
    EOF

    type '<C-n><C-n>Vchi!<Esc>'

    after <<-EOF
      hi!
      hi!
    EOF
  end
end
