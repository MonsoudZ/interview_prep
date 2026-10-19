class FeedController < ApplicationController
  def index
    organization = request.headers["X-Organization-ID"].to_s
    return failure(:unauthorized, "Organization required") unless positive_decimal?(organization)
    limit = params.key?(:limit) ? params[:limit].to_s : "10"
    return failure(:bad_request, "Invalid limit") unless positive_decimal?(limit) && limit.to_i <= 50
    before = params[:before].to_s if params.key?(:before)
    return failure(:bad_request, "Invalid cursor") if before && !positive_decimal?(before)
    scope = Post.where(organization_id: organization.to_i)
    scope = scope.where("posts.id < ?", before.to_i) if before
    page = scope.order(id: :desc).limit(limit.to_i + 1).preload(:author).to_a
    more = page.length > limit.to_i
    page = page.first(limit.to_i)
    counts = Comment.where(post_id: page.map(&:id)).group(:post_id).count
    items = page.map { |post| { id: post.id, body: post.body, author_name: post.author.name, comments_count: counts.fetch(post.id, 0) } }
    render json: { items: items, next_cursor: more ? page.last.id : nil }
  end
  private
  def positive_decimal?(value)
    value.match?(/\A[1-9][0-9]*\z/)
  end
  def failure(status, message)
    render json: { errors: { base: [message] } }, status: status
  end
end
