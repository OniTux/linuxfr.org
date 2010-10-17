# encoding: UTF-8
#
# == Schema Information
#
# Table name: nodes
#
#  id                :integer(4)      not null, primary key
#  content_id        :integer(4)
#  content_type      :string(255)
#  score             :integer(4)      default(0)
#  interest          :integer(4)      default(0)
#  user_id           :integer(4)
#  public            :boolean(1)      default(TRUE)
#  cc_licensed       :boolean(1)      default(FALSE)
#  comments_count    :integer(4)      default(0)
#  last_commented_at :datetime
#  created_at        :datetime
#  updated_at        :datetime
#

# The node is attached to each content.
# It helps organizing some common stuff between the contents,
# and facilitates the transformation of one content to another.
#
class Node < ActiveRecord::Base
  belongs_to :user     # can be NULL
  belongs_to :content, :polymorphic => true, :inverse_of => :node
  has_many :comments, :inverse_of => :node
  has_many :taggings, :dependent => :destroy, :include => :tag
  has_many :tags, :through => :taggings, :uniq => true

  scope :visible, where(:public => true)
  scope :by_date, order('created_at DESC')
  scope :public_listing, lambda {|type,order| visible.where(:content_type => type.to_s).order("#{order} DESC") }
  scope :on_dashboard, lambda {|type| public_listing(type, "created_at") }

### Interest ###

  after_create :compute_interest
  def compute_interest
    coeff = content_type.constantize.interest_coefficient
    stmt  = "UPDATE nodes SET interest=(score * #{coeff} + UNIX_TIMESTAMP(created_at) / 1000) WHERE id=#{self.id}"
    connection.update_sql(stmt)
  end

### Votes ###

  def vote_by?(user_id)
    $redis.exists("nodes/#{self.id}/votes/#{user_id}")
  end

  def vote_for(user)
    vote(user, 1)
  end

  def vote_against(user)
    vote(user, -1)
  end

  def vote(user, value)
    key  = "nodes/#{self.id}/votes/#{user.id}"
    prev = $redis.getset(key , value)
    return if prev.to_i == value
    value *= 2 if prev
    $redis.expire(key, 7776000) # 3 months
    $redis.incrby("users/#{self.user_id}/diff_karma", value)
    Account.decrement_counter(:nb_votes, user.account.id) unless user.amr?
    connection.update_sql("UPDATE nodes SET score=score + #{value} WHERE id=#{self.id}")
    compute_interest
    vote_on_candidate_news(value) if content_type == "News" && content.candidate?
  end

  def vote_on_candidate_news(value)
    word = value > 0 ? "pour" : "contre"
    who  = user.account.login
    if value.abs == 2
      $redis.lrem("nodes/#{self.id}/pour", 1, who)
      $redis.lrem("nodes/#{self.id}/contre", 1, who)
    end
    $redis.rpush("nodes/#{self.id}/#{word}", who)
    Board.create_for(content, :user => user, :kind => "vote", :message => "#{who} a voté #{word}")
  end

  def voters_for
    $redis.lrange("nodes/#{self.id}/pour", 0, -1).to_sentence
  end

  def voters_against
    $redis.lrange("nodes/#{self.id}/contre", 0, -1).to_sentence
  end

### Comments ###

  def threads
    Threads.all(self.id)
  end

### Readings ###

  def read_by(user_id)
    $redis.set("readings/#{self.id}/#{user_id}", Time.now.to_i)
    $redis.expire("readings/#{self.id}/#{user_id}", 7776000) # 3 months
  end

  def self.last_reading(node_id, user_id)
    time = $redis.get("readings/#{node_id}/#{user_id}")
    time && Time.at(time.to_i)
  end

  def read_status(user)
    r = Node.last_reading(self.id, user.id) if user
    return :not_read if r.nil?
    return :no_comments if last_commented_at.nil?
    return :new_comments if r < last_commented_at
    return :read
  end

### Tags ###

  def set_taglist(list, user)
    self.class.transaction do
      TagList.new(list).each do |tagname|
        tag = Tag.find_or_create_by_name(tagname)
        taggings.create(:tag_id => tag.id, :user_id => user.id)
      end
    end
  end

  def popular_tags(nb=7)
    Tag.joins(:taggings).
        where("taggings.node_id" => self.id).
        group("tags.id").
        order("COUNT(tags.id) DESC").
        limit(nb)
  end

end
