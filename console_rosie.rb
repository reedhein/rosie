require 'pry'
require 'pathname'
require 'pdf-reader'
require 'awesome_print'
require 'tesseract'
require 'shellwords'
require 'rmagick'
require 'grim'
require_relative '../global_utils/global_utils'
require 'active_support/time'
reader = nil
text = nil
file = 'Exit Letter.pdf'
File.open(file, 'rb') do |io|
  reader = PDF::Reader.new(io)
  text = reader.page(1).text
end
r = reader

puts 'derp derp'
class Rosie
  include Utils
  attr_reader :sf_client

  def initialize(limit: nil, project: 'rosie_migration', id: nil, environment: 'production', offset: 0)
    @id               = id
    @limit            = limit
    @offset           = File.open('offset', 'r').read.to_i
    @local_repository = '/Users/voodoologic/Sandbox/pdf_project'
    @local_cases      = '/Users/voodoologic/Sandbox/backup/Cases'
    @local_opp        = '/Users/voodoologic/Sandbox/backup/Opportunity'
    @pdf_name         = 'funtimes.pdf'
    @png_name         = 'funtimes.png'
    Utils.environment = @environment = environment
    @sf_client        = Utils::SalesForce::Client.instance
    @box_client       = Utils::Box::Client.instance
    @tesseract        = Tesseract::Engine.new {|e| e.language = :eng }
    @do_work          = true
    @meta             = DB::Meta.first_or_create(project: project)
    @offset_date      = @meta.offset_date
  end

  def peform
    first_time = true
    while @do_work == true do
      @do_work = false
      search_for_pdf.each do |pdf|
        CSV.open('funtimes.csv', 'ab', headers: true, col_sep: ';') do |csv|
          csv << ["Name", "Exit Date", "Timeshare", "Folder Label"] if first_time
          first_time = false
          @do_work = true
          next if pdf.name.split('.').last !~ /pdf/i
          if sf_name = is_opportunity?(pdf)
            query = construct_query(sf_name)
            opportunities = @sf_client.custom_query(query: query)
            next if opportunities.empty?
            next if opportunities.count > 1
            reference_id = opportunities.first.id
          else
            reference_id = pdf.path.split('/')[-3]
          end
          exit_date = nil
          base_path = Pathname.new([@local_repository, reference_id].join('/'))
          base_path.mkpath
          file_path = base_path + pdf.name
          if !file_path.exist?
            pdf_content = pdf.download
            File.open(file_path, 'w') do |f|
              f << pdf_content
            end
          else
            pdf_content = File.open(file_path).read
            puts 'we already have that file'
          end
          io = StringIO.new(pdf_content)
          begin
            local_pdf = PDF::Reader.new(io)
          rescue
            next
          end
          begin
            if !local_pdf.page(1).text.present? #'\f'.empty? returns false
              convert_file_to_image(file_path)
              words, exit_date  = read_image_to_text(file_path)
              next unless exit_date
            else
              words = local_pdf.page(1).text
            end
          rescue
            next
          end
          match = words.squish.match(/(\d{1,2}\/\d{1,2}\/\d{2,4})(.+)Timeshare\:(.+?)Timeshare/)
          if match
            exit_date ||= match[1]
            name = match[2]
            timeshare = match[3]
          else
            ap words
          end
          next unless exit_date
          if words !~ /855-733-3434/
            puts 'believed to not be our letter'
            next
          end
          puts [exit_date, name, timeshare, reference_id].join(' ')
          csv << [name, exit_date, timeshare, reference_id]
        end
      end
      @offset += 200
      File.open('offset', 'w') do |f|
        f << @offset
      end
      puts @offset
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
    image_name = file_path.basename.to_s.gsub(/\.pdf$/, '.png')
    file_path.dirname + image_name
  end

  def read_image_to_text(file_path)
    image_path = file_path_to_image_path(file_path)
    begin
      text_object = @tesseract.text_for(image_path.to_s)
      date = get_date(text_object)
      [text_object.squish, date]
    rescue
      [nil, nil]
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
    binding.pry
    @box_client.search('Exit Letter*.pdf', limit: 200, offset: @offset)
  end
end

r = Rosie.new
r.peform
ap r
binding.pry

puts 'fun times'
