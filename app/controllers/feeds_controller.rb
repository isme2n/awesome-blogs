require 'rss'
require 'open-uri'

class FeedsController < ApplicationController
  CACHE_EXPIRING_TIME = Rails.env.production? ? 2.hours : 2.minutes

  def index
    # x.scan(/xmlUrl=".*?"/).each {|x| puts x[7..-1] + ','}
    category = params[:category] || 'dev'

    feeds = Rails.configuration.feeds[category]

    @rss = RSS::Maker.make('atom') do |maker|
      maker.channel.author = 'Benjamin'.freeze
      maker.channel.about = '한국의 좋은 개발자 블로그 글들을 매일 배달해줍니다.'.freeze
      maker.channel.title = channel_title(category)

      Parallel.each(feeds, in_threads: 30) do |feed_h|
        begin
          feed_url = feed_h[:feed_url]
          feed = Rails.cache.fetch(feed_url, expires_in: CACHE_EXPIRING_TIME) do
            puts "cache missed: #{feed_url}"
            Feedjira::Feed.fetch_and_parse(feed_url)
          end
          # puts "FEED: #{feed.inspect}"

          feed.entries.each do |entry|
            if entry.published < Time.now - 7.days
              next
            end
            maker.items.new_item do |item|
              #puts entry.inspect  if entry.title == '밟아야 사는 사회'
              item.link = entry.url || entry.entry_id
              item.title = entry.title
              item.updated = entry.published.localtime
              item.summary = entry.content || entry.summary
              item.author = entry.author || feed_h[:author_name] || feed.title
              if item.link.blank?
                Rails.logger.error("ERROR - url shouldn't be null: #{entry.inspect}")
              end
            end
          end
        rescue => e
          puts "ERROR: #{e.inspect}"
          puts "ERROR: URL => #{feed_url}"
          next
        end
      end
      maker.channel.updated = maker.items.max_by { |x| x.updated.to_i }&.updated&.localtime || Time.now
    end

    group = params[:group] || 'none'
    report_google_analytics(group, group, request.user_agent)

    # binding.pry
    respond_to do |format|
      format.xml { render xml: @rss.to_xml }
      format.json
    end
  end

  def report_google_analytics(cid, title, ua)
    RestClient.post('http://www.google-analytics.com/collect',
      {
        v: '1',
        tid: 'UA-90528160-1',
        cid: SecureRandom.uuid,
        t: 'pageview',
        dh: 'awesome-blogs.petabytes.org',
        dp: cid.to_s,
        dt: title,
      },
      user_agent: ua
    )
  end

  def channel_title(category)
    case category
    when 'dev'
      '한국 개발자 블로그 모음'.freeze
    when 'company'
      '한국 회사 기술 블로그 모음'.freeze
    when 'non-dev'
      '기획 및 창업/투자자 블로그 모음'.freeze
    else
      raise ArgumentError.new
    end
  end
end