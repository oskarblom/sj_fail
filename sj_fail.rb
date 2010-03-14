require 'rubygems'
require 'hpricot'
require 'open-uri'
require 'htmlentities'
require 'digest/md5'
require 'cgi'
require 'json'


class BitlyUrlShortener
  LOGIN = 'sjfail'
  API_KEY = 'R_6ff1fd33689cf2362af1ce72fbc73673'

  def shorten(url)
    encoded_url = CGI.escape(url)
    json_resp = Net::HTTP.get(
      URI.parse("http://api.bit.ly/shorten?version=2.0.1&longUrl=" +
        "#{encoded_url}&login=#{LOGIN}&apiKey=#{API_KEY}")
    )    
    result = JSON.parse(json_resp)
    return result['results'][url]['shortUrl']
  end
  
end

class TweetError < RuntimeError; end

class SjTweeter
  MESSAGE_MAX_LENGTH = 140
  
  def initialize(login, passwd)
    @login = login
    @passwd = passwd
    @url_shortener = BitlyUrlShortener.new
  end
  
  def tweet(sj_info)
    begin
      message = get_message(sj_info)
      post(message)
      sj_info.posted = true
    rescue NoMethodError => e
      $stderr.puts("Something went wrong when parsing message. Won't try to send this message. #{$!}" )
      sj_info.posted = true
    rescue 
      $stderr.puts("Something went wrong when sending message. Will try to resend later.  #{$!}" )
      sj_info.posted = false
    end
  end
  
  private
  
  def get_message(sj_info)
    link_url = @url_shortener.shorten(sj_info.link)
    msg = shorten("#{sj_info.type}. #{sj_info.header}. ")
    remaining_chars = MESSAGE_MAX_LENGTH - (msg.scan(/./u).length + link_url.length)
    desc = shorten(sj_info.desc)
    msg << desc.scan(/^.{0,#{remaining_chars-1}}/u)[0] + " " + link_url
    return msg
  end
  
  def post(message)
    raise TweetError.new("Error posting") unless Net::HTTP.post_form(
      URI.parse("http://#{@login}:#{@passwd}@www.twitter.com/statuses/update.xml"),
      {'status' => message}
    ).is_a?(Net::HTTPOK)
  end
  
  def shorten(message)
    return message if message.length < 1
    short = message.clone
    short = short.gsub(/(ban|fordons|förar|lok|personal|signal|spår|tåg|vagn|växel)\-?(?=arbete|brist|byte|fel|kö|problem|underhåll|vändning)/ui) { |s|
      s.scan(/^./).first.upcase + '-'
    }
    short = short.gsub(/(p)å grund av /ui, '\1.g.a. ')
    short = short.gsub(/(t|fr)(ill|ån) och med /ui, '\1.o.m. ')
    short = short.gsub(/(f)ör närvarande(?=\.| )/ui, '\1.n.')
    short = short.gsub(/(t)ills *vidare(?=\.| )/ui, '\1.v.')
    short = short.gsub(/(n)edanstående/ui, '\1edanst.')
    short = short.gsub(/(i)nformations?/ui, '\1nfo')
    short = short.gsub(/(o)rdinarie/ui, '\1rd.')
    short = short.gsub(/(e)nligt?/ui, '\1nl.')
    short = short.gsub(/(s)törning(s|ens?|ars?(nas?)?)?/ui, '\1törn.')
    short = short.gsub(/(a)vgång(s|ens?|ars?(nas?)?)?/ui, '\1vg.')
    short = short.gsub(/(a)nkomst(ens?|ers?(nas?)?)?/ui, '\1nk.')
    short = short.gsub(/(p)eriod(ens?|ers?(nas?)?)?/ui, '\1er.')
    short = short.gsub(/(i)nställ(da?|t|e?s)/ui, '\1nst.')
    short = short.gsub(/(f)örsen(ade?|at|ings?(ars?(nas?)?)?)/ui, '\1örs.')
    short = short.gsub(/(s)träck(an?s?|ors?(nas?)?)/ui, '\1tr.')
    short = short.gsub(/(b)eräkn(a(d|r|s|t)?)/ui, '\1er.')
    short = short.gsub(/(e)rs[aä]tt(a|e?s|er|nings?)?/ui, '\1rs.')
    short = short.gsub(/(t)illfäll(e(n|t)?|ig(het|a|t)?)/ui, '\1illf.')
    short = short.gsub(/(i) +(dag|morgon|går)/ui, '\1\2')
    short = short.gsub(/ och /ui, ' & ')
    short = short.gsub(/X *2000/ui, 'X2k')
    short = short.gsub(/intercity/ui, 'IC')
    short = short.gsub(/regional/ui, 'Reg.')
    short = short.gsub(/(nat)?tåg +(\d+)/ui, 'T:\2')
    short = short.gsub(/(kl)ockan /ui, '\1. ')
    short = short.gsub(/ den +(\d+)/ui, ' \1')
    short = short.gsub(/(f|e)(ör|fter)middags?/ui, '\1.m.')
    short = short.gsub(/(må|ti|on|to|fr|lö|sö)(n|s|rs?|e)dag(en)?/ui, '\1.')
    short = short.gsub(/(jan|feb|aug|sep|okt|nov|dec)(r?uari|usti|t?ember|ober)/ui, '\1.')
    short = short.gsub(/ *\- */u, '-')
    short = short.gsub(/([^\-,\. ]+? ?[^\-,\. ]+?)\-([^\-,\. ]+? ?[^\-,\. ]+?)\-(\1)/u, '\1<->\2')
    short = short.gsub(/  +/u, ' ')
    short = short.gsub(/\.\.+/u, '.')
    return short
  end
end

class SjInfo
  LINK_PREFIX = 'http://www.sj.se'
  OLD_CRITERIA = 3600 * 48
  attr_reader :type, :header, :desc, :md5hash
  attr_accessor :posted

  def initialize(args)        
    @type = args['type']
    @header = args['header']
    @desc = args['desc']
    @link = args['link']
    @md5hash = Digest::MD5.hexdigest(@link)
    @created = Time.now.to_i
    @posted = false
  end
  
  def link
    LINK_PREFIX + @link
  end
  
  def old?
    (Time.now.to_i - OLD_CRITERIA >= @created)
  end
  
  def posted?
    @posted
  end
  
end

class SjScraper
  TYPE_PATH = "/html/body/div/div[4]/div[3]/form/table/tr/td[2]/h3"
  HEADER_PATH = "/html/body/div/div[4]/div[3]/form/table/tr/td[2]/h4"
  DESC_PATH = "/html/body/div/div[4]/div[3]/form/table/tr/td/p[@class='textform']"
  LINK_PATH = "/html/body/div/div[4]/div[3]/form/table/tr/td[2]/a"
  BASE_SEARCH_URL = 'http://www.sj.se/sj/jsp/polopoly.jsp?d=288&l=sv&from=&to=&searchStation=S%D6K&date='

  def initialize
      @html_coder = HTMLEntities.new
      @result = []
      parse_info
  end
  
  def get_info
      @result.reverse
  end
  
  private
  
  def parse_info
    doc = nil
    open(get_uri) { |f| doc = Hpricot(f.read) }
    (doc/TYPE_PATH).zip(
        (doc/HEADER_PATH), (doc/DESC_PATH), (doc/LINK_PATH)).each do |row|
            @result << extract_result(row)
    end
  end

  def get_uri
    time = Time.new
    BASE_SEARCH_URL + "#{time.year}-#{time.month}-#{time.day}"
  end

  protected
  
  def extract_result(row)
    return SjInfo.new(
      'type' => @html_coder.decode(row[0].inner_html.strip).gsub(/<\/?[^>]*>/, ""), 
      'header' => @html_coder.decode(row[1].inner_html.strip).gsub(/<\/?[^>]*>/, ""), 
      'desc' => @html_coder.decode(row[2].inner_html.strip).gsub(/<\/?[^>]*>/, ""), 
      'link' => @html_coder.decode(row[3].attributes['href']).gsub(/<\/?[^>]*>/, "")
    )
  end

end

class SjPersistor
  STORAGE_PATH = 'repository'
  
  def self.put(sj_list)        
    File.open(STORAGE_PATH, 'w+') do |f|
        Marshal.dump(sj_list, f)
    end        
  end
  
  def self.get
    sj_list = []
    begin
        File.open(STORAGE_PATH, 'r+') do |f|
            sj_list = Marshal.load(f)
        end
    rescue
        File.new(STORAGE_PATH, 'w')
    end
    sj_list
  end
end

def main
  unless ARGV.length == 2
      $stderr.puts('Provide twitter login and password as args.')
      exit(1) 
  end

  stored_info = SjPersistor.get
  tweeter = SjTweeter.new(ARGV[0], ARGV[1])

  stored_info.each do |item|
    tweeter.tweet(item) unless item.posted?
    stored_info.delete(item) if item.old?
  end

  scraper = SjScraper.new
  scraped_info = scraper.get_info
  if scraped_info.length > 5
    scraped_info = scraped_info.last(5)
  end

  scraped_info.each do |item|
    matches = stored_info.select{|i| i.md5hash == item.md5hash}
    unless matches.length > 0
      tweeter.tweet(item)
      stored_info << item
    end
  end

  SjPersistor.put(stored_info)
end

main
