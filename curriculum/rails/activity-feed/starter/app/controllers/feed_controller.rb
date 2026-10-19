class FeedController < ApplicationController
  def index
    posts = Post.all.sort_by(&:id).reverse.take((params[:limit] || 10).to_i)
    render json: { items: posts.map { |post| { id: post.id, body: post.body,
      author_name: post.author.name, comments_count: post.comments.count } }, next_cursor: nil }
  end
end
