require 'rubygems'
require 'mechanize'
require 'logger'
require 'csv'
require "kconv"
require 'action_mailer'
require 'pit'

class JisMailer < ActionMailer::Base
  @@default_charset = 'iso-2022-jp'
  def message(recipient, my_subject, my_body)
    from 'deployer@its.actindi.net'
    recipients recipient
    subject Kconv.tojis(my_subject)
    body Kconv.tojis(my_body)
  end
end

class OverDue
  attr_accessor :login_url, :username, :password, :mail_to, :tasks, :fields

  def initialize
    config = Pit.get("over_due", :require => {
      "login_url" => "login url in redmine",
      "username"  => "your email in redmine",
      "password"  => "your password in redmine",
      "mail_to"   => "email for alert"
    })

    @login_url = config["login_url"]
    @username  = config["username"]
    @password  = config["password"]
    @mail_to   = config["mail_to"]
    @fields    = []
  end

  def fetch
    agent = WWW::Mechanize.new
    logger = Logger.new STDOUT
    logger.level = Logger::INFO
    #agent.log = logger

    agent.get(@login_url)
    agent.page.form_with(:action => "/login") do |form|
      form.field_with(:name => 'username').value = @username
      form.field_with(:name => 'password').value = @password
      form.click_button
    end

    agent.page.link_with(:text => "チケットを全て見る").click
    agent.page.link_with(:text => "期限過ぎてる").click
    agent.page.link_with(:text => "CSV").click

    csv = CSV::StringReader.new(agent.page.body)
    @fields = csv.shift
    @tasks = csv.map do |row|
      hash = {}
      @fields.each_with_index do |field, i|
        hash[field] = row[i]
      end
      hash
    end
    self
  end

  def send
    pics = []
    tasks = []
    @tasks.each do |task|
      pics << task["担当者"]
    end

    pics = pics.uniq.delete_if {|n| n == ""}

    return nil unless pics.size > 0

    body = <<-EOS
#{pics.join("さん ")}さん

お疲れ様です。駒形です。

現在、期限の過ぎているタスクがあります。
直ちに処理をお願いします。

以上、宜しくお願い致します。
    EOS

    ActionMailer::Base.delivery_method = :sendmail
    JisMailer.deliver_message(
      @mail_to,
      "期限切れのタスクについて",
      body)

    pics.each do |pic|
      body = <<-EOS
#{pic}さん

お疲れ様です。駒形です。

再発防止と他のメンバーとの事例共有のため、
タスクの期限が過ぎてしまった理由とその対策をお教えください。

参照：
https://sites.google.com/a/actindi.net/share/project/shigoto-no-kouritsu-ka-purojekuto#ticket

以上、以上宜しくお願い致します。
      EOS

      JisMailer.deliver_message(
        @mail_to,
        "期限切れのタスクの原因と対策",
        body)
    end
  end
end

def OverDue
  OverDue.new.fetch.send
end
