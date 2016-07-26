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
class Rosie
  include Utils
  attr_reader :file_path, :image_path

  def initialize(pdf_path: nil, image_path: nil, image_destination: nil)
    @pdf_path           = pdf_path
    @image_path         = image_path
    @image_destination  = image_destination || '/Users/voodoologic/temp_image.png'
    @tesseract          = Tesseract::Engine.new {|e| e.language = :eng }
  end

  def read_text
    @image_path = create_image_from_pdf if @image_path.nil?
    read_image_to_text
  end

  private

  def create_image_from_pdf
    pdf = Grim.reap(@pdf_path.to_s)
    pdf[0].save(@image_destination)
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

  def read_image_to_text
    @tesseract.text_for(@image_destination)
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

end

