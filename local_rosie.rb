require 'pry'
require 'pathname'
require 'pdf-reader'
require 'awesome_print'
require 'tesseract'
require 'shellwords'
require 'rmagick'
require 'grim'
require_relative '../global_utils/global_utils'
require_relative 'rosie'
require 'active_support/time'
class LocalRosie
  include Utils
  attr_reader :sf_client

  def initialize(environment: 'production')
    @local_repository = '/Users/voodoologic/Work/rosie/Exit Letters'
    Utils.environment = @environment = environment
    @sf_client        = Utils::SalesForce::Client.instance
    @box_client       = Utils::Box::Client.instance
    @tesseract        = Tesseract::Engine.new {|e| e.language = :eng }
  end

  def peform
    first_time = true
    Dir.glob([@local_repository, '*.pdf'].join('/')).each do |pdf_path|
      CSV.open('funtimes2.csv', 'ab', headers: true, col_sep: ';') do |csv|
        csv << ["Exit Date", "Customer", "Contract"] if first_time
        first_time = false
        pdf = PDF::Reader.new(pdf_path)
        pdf.binmode if pdf.respond_to?(:binmode)
        if pdf.page(1).text.present?
          date, customer, contract = attempt_extraction(pdf.page(1).text)
          next unless date && customer && contract
        else
          text = Rosie.new(pdf_path: pdf_path).read_text
          exit_date, customer, contract = get_meta(text)
          match = text.squish.match(/(\d{1,2}\/\d{1,2}\/\d{2,4})(.+)Timeshare\:(.+?)Timeshare/)
          if match && exit_date.nil?
            exit_date ||= match[1]
            customer = match[2]
            contract = match[3]
          end
          ap text
        end
        ap [date, customer, contract]
        csv << [date, customer, contract]
      end
    end
  end
  private

  def is_opportunity?(pdf)
    match = pdf.path.split('/')[-2].match(/(.+)\ -\ Finance$/)
    if match
      puts "opportunity"
      match[1] 
    else
      false
    end
  end

  def attempt_extraction(text)
    if text.match(/I would like to congratulate you for officially exiting your timeshare!/)
      condenced_email = text.lines.delete_if do |line|
        line == "\n"
      end
      date = Date.parse(condenced_email[0])
      customer = condenced_email[1]
      contract = condenced_email[2]
      [date, customer, contract]
    end
  end
  def local_pdf
    pdfs = Dir.glob([@local_cases, '**', '*.pdf'].join('/')) << Dir.glob([@local_opp, '**', '*.pdf'].join('/'))
    pdfs.flatten.select do |path|
      Pathname.new(path).basename.to_s =~ /Exit Letter/i
    end
  end

  def convert_file_to_image(file_path)
    image_path = file_path_to_image_path(file_path)
    begin
      pdf = Grim.reap(file_path.to_s)
      pdf[0].save(image_path.to_s.shellescape) unless image_path.exist?
    rescue => e
      ap e.backtrace
      binding.pry
    end
  end

  def file_path_to_image_path(file_path)
    image_name = Pathname.new(file_path).basename.to_s.gsub(/\.pdf$/, '.png')
    file_path.dirname + image_name
  end

  def get_meta(text_object)
    has_number_gone_by = false
    header_phone_index = nil
    text_object.each_line.select.with_index do |line , i|
      has_number_gone_by ||= is_line_phone_on_header?(line)
      header_phone_index ||= i if has_number_gone_by
      if header_phone_index
        (i < header_phone_index + 5 ) && line != "\n"
      end
    end
  end

  def get_date(text_object)
    has_number_gone_by = false
    text_object.each_line.detect.with_index do |line , i|
      has_number_gone_by ||= is_line_phone_on_header?(line)
      begin
        Date.parse(line) && i < 10 && has_number_gone_by
      rescue
        puts i
        false
      end
    end
  end

  def construct_query(sf_name)
    if @id
      query = " SELECT Name, Id, createdDate, (SELECT Id, Name FROM Attachments) FROM Opportunity WHERE id = '#{@id}'"
    elsif @offset_date
      query = <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity 
        CreatedDate >= #{@offset_date} 
        ORDER BY CreatedDate ASC
      EOF
    else
      query = <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity WHERE Name = '#{sf_name.gsub("'", %q(\\\'))}'
      EOF
    end
    query
  end

  def is_line_phone_on_header?(line)
    line =~ /855-733-3434/
  end

  def search_for_pdf
    puts "*"*88
    puts @offset
    puts "*"*88
    @box_client.search('Exit Letter*.pdf', limit: 200, offset: @offset)
  end
end

r = LocalRosie.new
r.peform
ap r
binding.pry

puts 'fun times'
