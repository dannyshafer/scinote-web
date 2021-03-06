class Users::RegistrationsController < Devise::RegistrationsController

  before_action :load_paperclip_vars

  def avatar
    style = params[:style] || "icon_small"
    redirect_to current_user.avatar.url(style.to_sym), status: 307
  end

  def signature
    respond_to do |format|
      format.json {

        # Changed avatar values are only used for pre-generating S3 key
        # and user object is not persisted with this values.
        current_user.empty_avatar params[:file_name], params[:file_size]

        unless current_user.valid?
          render json: {
            status: 'error',
            errors: current_user.errors
          }
        else
          render json: {
            posts: generate_upload_posts
          }
        end
      }
    end
  end

  def update_resource(resource, params)
    @user_avatar_url = avatar_path(:thumb)

    if @direct_upload
      if params.include? :avatar_file_name
        file_name = params[:avatar_file_name]
        file_ext = file_name.split(".").last
        params[:avatar_content_type] = Rack::Mime.mime_type(".#{file_ext}")
        resource.avatar.destroy
      end
    end

    if params.include? :change_password
      # Special handling if changing password
      params.delete(:change_password)
      if (
        resource.valid_password?(params[:current_password]) and
        params.include? :password and
        params.include? :password_confirmation and
        params[:password].blank?
      ) then
        # If new password is blank and we're in process of changing
        # password, add error to the resource and return false
        resource.errors.add(:password, :blank)
        false
      else
        resource.update_with_password(params)
      end
    elsif params.include? :change_avatar
      params.delete(:change_avatar)
      unless params.include? :avatar
        resource.errors.add(:avatar, :blank)
        false
      else
        resource.update_without_password(params)
      end
    elsif params.include? :email or params.include? :password
      # For changing email or password, validate current_password
      resource.update_with_password(params)

    else
      # For changing some attributes, no current_password validation
      # is required
      resource.update_without_password(params)
    end
  end

  # Override default registrations_controller.rb implementation
  # to support JSON
  def update
    change_password = account_update_params.include? :change_password
    respond_to do |format|
      self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
      prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email)

      resource_updated = update_resource(resource, account_update_params)
      yield resource if block_given?
      if resource_updated
        # Set "needs confirmation" flash if neccesary
        if is_flashing_format?
          flash_key = update_needs_confirmation?(resource, prev_unconfirmed_email) ?
            :update_needs_confirmation : :updated
          set_flash_message :notice, flash_key
        end

        # Set "password successfully updated" flash if neccesary
        if change_password
          set_flash_message :notice, :password_changed
        end

        format.html {
          sign_in resource_name, resource, bypass: true
          respond_with resource, location: edit_user_registration_path
        }
        format.json {
          flash.keep
          sign_in resource_name, resource, bypass: true
          render json: { status: :ok }
        }
      else
        clean_up_passwords resource
        format.html {
          respond_with resource, location: edit_user_registration_path
        }
        format.json {
          render json: self.resource.errors,
          status: :unprocessable_entity
        }
      end
    end
  end

  def create

    # Create new organization for the new user
    @org = Organization.new
    @org.name = params[:organization][:name]

    build_resource(sign_up_params)

    valid_org = @org.valid?
    valid_resource = resource.valid?

    if valid_org and valid_resource

      # this must be called after @org variable is defined. Otherwise this
      # variable won't be accessable in view.
      super do |resource|

        if resource.valid? and resource.persisted?
          @org.created_by = resource  #set created_by for oraganization
          @org.save

          # Add this user to the organization as owner
          UserOrganization.create(
            user: resource,
            organization: @org,
            role: :admin
          )
        end
      end

    else
      render :new
    end
  end

  protected

  def load_paperclip_vars
    @direct_upload = ENV['PAPERCLIP_DIRECT_UPLOAD']
  end

  # Called upon creating User (before .save). Permits parameters and extracts
  # initials from :full_name (takes at most 4 chars). If :full_name is empty, it
  # uses "PLCH" as a placeholder (user won't get error complaining about
  # initials being empty.
  def sign_up_params
    tmp = params.require(:user).permit(:full_name, :initials, :email, :password, :password_confirmation)
    initials = tmp[:full_name].titleize.scan(/[A-Z]+/).join()
    initials = initials.strip.empty? ? "PLCH" : initials[0..3]
    tmp.merge(:initials => initials)
  end

  def account_update_params
    params.require(:user).permit(
      :full_name,
      :initials,
      :avatar,
      :avatar_file_name,
      :email,
      :password,
      :password_confirmation,
      :current_password,
      :change_password,
      :change_avatar
    )
  end

  def generate_upload_posts
    posts = []
    file_size = current_user.avatar_file_size
    content_type = current_user.avatar_content_type
    s3_post = S3_BUCKET.presigned_post(
      key: current_user.avatar.path[1..-1],
      success_action_status: '201',
      acl: 'private',
      storage_class: "STANDARD",
      content_length_range: file_size..file_size,
      content_type: content_type
    )
    posts.push({
      url: s3_post.url,
      fields: s3_post.fields
    })

    current_user.avatar.options[:styles].each do |style, option|
      s3_post = S3_BUCKET.presigned_post(
        key: current_user.avatar.path(style)[1..-1],
        success_action_status: '201',
        acl: 'public-read',
        storage_class: "REDUCED_REDUNDANCY",
        content_length_range: 1..(1024*1024*50),
        content_type: content_type
      )
      posts.push({
        url: s3_post.url,
        fields: s3_post.fields,
        style_option: option,
        mime_type: content_type
      })
    end

    posts
  end

  private

  # Redirect to login page after signing up
  def after_sign_up_path_for(resource)
    new_user_session_path
  end

  # Redirect to login page after signing up
  def after_inactive_sign_up_path_for(resource)
    new_user_session_path
  end
end
