###############################################################################
#                                                                             #
#         #                       #  ###             #           #            #
#            ### # # ### ##   ##  #    # ### ### # # ###     ### ###          #
#         #  # # # # #   # # # #  #  ### ##  # # # # # #     #   # #          #
#         #  ### ### #   # # ###  ## #   ### ### ### ###     #   ###          #
#        #                           ###     #            #                   #
#                                                                             #
#      journal2epub.rb 0.1 (c) 2011 Louis St-Amour, MIT Licensed (Expat)      #
# Command-line tool to convert an issue of code4lib journal into epub format. #
#                                                                             #
# Installation (ideally with rvm): gem install bundler && bundle install      #
#                                                                             #
# Usage: ruby journal2epub.rb --issue <number>                                #
#                           e.g. ruby journal2epub.rb --issue 12 will convert #
#                     http://journal.code4lib.org/issues/issue12 into 12.epub #
###############################################################################

require 'open-uri'
require 'fileutils'
require 'digest/sha1'
require 'erb'

require 'rubygems'
require 'bundler/setup'

require 'nokogiri'
require 'trollop'
require 'mime/types'
require 'zip/zip'
require 'tidy_ffi'

# Thanks to Sam Stephenson, http://refactormycode.com/codes/281-given-a-hash-of-variables-render-an-erb-template
class Hash
  def to_binding(object = Object.new)
    object.instance_eval("def binding_for(#{keys.join(",")}) binding end")
    object.binding_for(*values)
  end
end

opts = Trollop::options do
  version "journal2epub.rb 0.1 (c) 2011 Louis St-Amour, MIT Licensed (Expat)"
  banner <<-EOS
#{version}
Command-line tool to convert an issue of code4lib journal into epub format.

Usage: ruby journal2epub.rb [options]

           Possible [options]
==================   ========================
EOS
  opt :issue, "Issue number to download", :default => "12" #:type => :string
end
Trollop::die :issue, "is required" if opts[:issue].nil?

issues_url = 'http://journal.code4lib.org/issues'
issues_doc = Nokogiri(open(issues_url).read)
issues_doc.encoding = 'UTF-8'
issue_date = issues_doc.xpath("//*[starts-with(a,'Issue " + 
                          opts[:issue] + ",')]").first.text.split(", ")[1]

url = "http://journal.code4lib.org/issues/issue"+opts[:issue]
doc = Nokogiri(open(url).read)
doc.encoding = 'UTF-8'
content = (doc/"#content")

issue = {
  :uri => url,
  :title => (content/"h1").first.text+', Code4Lib Journal',
  :uid => 'urn:uuid:'+Digest::SHA1.hexdigest(url), # Issues are unique per URL?
  :issn => '19405758',
  :now => Time.now.strftime("%Y-%m-%d"),
  :date => issue_date, # e.g. 2010-12-21
  :articles => (content/"div.article").map do |a|
    {
      :id => a[:id],
      :filename => "#{a[:id]}.xhtml",
      :title => (a/"h2").first.text,
      :url => (a/"a").first[:href], # Luckily always exists, always absolute.
      :author => (a/"p.author").first.text,
      :abstract => (a/"div.abstract").first.inner_html.strip,
      :sections => [],
    }
  end,
  :files => []
}

# Make a copy for us to work with...
dir = 'tmp'
FileUtils.rm_rf dir
FileUtils.cp_r 'epub_template', dir

issue[:articles].each do |article|
  article_doc = Nokogiri(open(article[:url]).read)
  article_doc.encoding = 'UTF-8'
  div = (article_doc/"div.article").first
  (div/"#issueDesignation").first.remove
  article[:html] = div.to_xhtml(:indent => 0, :encoding => 'UTF-8')
  result = ERB.new(File.read("#{dir}/OEBPS/template.html")).result(article.to_binding)
  tidy = TidyFFI::Tidy.new(result)
  tidy.options.drop_font_tags = true
  tidy.options.char_encoding = 'utf8'
  tidy.options.clean = true
  tidy.options.output_xhtml = true
  tidy.options.lower_literals = true
  tidy.options.numeric_entities = true
  tidy.options.drop_proprietary_attributes = true
  tidy.options.alt_text = ''
  tidy.options.doctype = 'strict'
  tidy.options.wrap = 0
  doc2 = Nokogiri(tidy.clean)
  doc2.encoding = 'UTF-8'
  #(doc2/'//meta[@name="generator"]').first.remove
  (doc2/"//html[@lang]").remove_attr('lang')
  (doc2/"//pre").remove_attr('name')
  (doc2/"//a").remove_attr('name')
  (doc2/"//a[@href]").each do |link|
    if link[:href] =~ %r{^/articles/}
      link['href'] = "http://journal.code4lib.org#{link[:href]}"
    end
    if link[:href] =~ %r{^http://journal.code4lib.org/articles/}
      fragment = link[:href].split('#')[1]
      issue[:articles].each do |a|
        if link[:href] == a[:url]
          link['href'] = a[:filename]
          link['href'] += fragment unless fragment.nil?
          break
        end
      end
    end
  end
  (doc2/"//*[@align]").remove_attr('align')
  (doc2/"//*[@width]").remove_attr('width')
  (doc2/"//*[@height]").remove_attr('height')
  doc2.xpath('//pre').each do |p|
    if p.text.strip.length == 0
      p.remove
    else
      p.inner_html = p.inner_html.gsub(%r{^\n+}, "\n")
    end
  end
  headings = doc2.xpath("//h2|//h3")
  puts article[:url]
  headings.each_with_index do |heading, j|
    heading['id'] ||= "epubsection#{j+1}"
    if heading.name.downcase == 'h2' || article[:sections].empty?
      article[:sections] << {
        :title => heading.text,
        :id => heading['id'],
        :sections => []
      }
    else
      article[:sections].last[:sections] << {
        :title => heading.text,
        :id => heading['id']
      }
    end
  end
  
  (doc2/'a img').each do |img|
    image_url = img.parent[:href]
    if(image_url =~ %r{^http://journal.code4lib.org/wp-content/uploads/})
      image_filename = "images/#{issue[:files].length}.#{image_url.split('.')[-1]}"
      img['src'] = image_filename
      img.parent.replace(img)
      File.open("#{dir}/OEBPS/"+image_filename, 'w') do |f|
        f.write open(image_url).read
      end
      issue[:files] << image_filename
    end
  end
  
  (doc2/"img").each do |img|
    image_url = img[:src]
    if(img[:src] =~ %r{^http://})
      image_filename = "images/#{issue[:files].length}.#{image_url.split('.')[-1]}"
      img['src'] = image_filename
      File.open("#{dir}/OEBPS/"+image_filename, 'w') do |f|
        f.write open(image_url).read
      end
      issue[:files] << image_filename
    end
  end
  
  # I've no idea why Nokogiri is doing this, but it is, so we must gsub...
  doctype_old = <<-EOS
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<?xml version="1.0" encoding="utf-8"??>
EOS
  doctype_new = <<-EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
	"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
EOS
  html_old = <<-EOS
<html xmlns="http://www.w3.org/1999/xhtml" xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
EOS
  html_new = <<-EOS
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
EOS
  xhtml = doc2.to_xhtml(:indent => 0, :encoding => 'UTF-8')
  xhtml.gsub!(doctype_old, doctype_new)
  xhtml.gsub!(html_old, html_new)
  File.open("#{dir}/OEBPS/#{article[:filename]}", 'w') do |f| 
    f.write xhtml
  end
end

# Delete article template from tmp dir when done ...
FileUtils.rm_f "#{dir}/OEBPS/template.html"

[dir+'/OEBPS/toc.ncx', dir+'/OEBPS/content.opf'].each do |filename|
  result = ERB.new(File.read(filename)).result
  File.open(filename, 'w') { |f| f.write result }
end

# Thank you mkepub, for inspiring the following rubyzip code -- Louis.
epubname = opts[:issue]+'.epub'
FileUtils.rm_f epubname

os = Zip::ZipOutputStream.new(epubname)
os.put_next_entry("mimetype", nil, nil, Zlib::NO_COMPRESSION)
os << "application/epub+zip"
os.close

zipfile = Zip::ZipFile.open(epubname)
Dir["#{dir}/**/*"].each do |path|
  archive_path = path.sub("#{dir}/", "")
  if !File.directory?(path) && !(archive_path == "mimetype")
    zipfile.add(archive_path, path)
  end
end
zipfile.commit

File.open("#{opts[:issue]}.log", 'w') do |f| 
  f.write `java -jar epubcheck-1.1/epubcheck-1.1.jar #{epubname} 2>&1`
end