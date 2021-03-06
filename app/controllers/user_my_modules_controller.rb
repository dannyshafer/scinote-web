class UserMyModulesController < ApplicationController
  before_action :load_vars
  before_action :check_view_permissions, only: [ :index ]
  before_action :check_edit_permissions, only: [ :index_edit ]
  before_action :check_create_permissions, only: [:new, :create]
  before_action :check_delete_permisisons, only: [:destroy]

  def index
    @user_my_modules = @my_module.user_my_modules

    respond_to do |format|
      format.json {
        render :json => {
          :html => render_to_string({
            :partial => "index.html.erb"
            })
        }
      }
    end
  end

  def index_edit
    @user_my_modules = @my_module.user_my_modules
    @unassigned_users = @my_module.unassigned_users
    @new_um = UserMyModule.new(my_module: @my_module)

    respond_to do |format|
      format.json {
        render :json => {
          :my_module => @my_module,
          :html => render_to_string({
            :partial => "index_edit.html.erb"
          })
        }
      }
    end
  end

  def new
    @um = UserMyModule.new(
      my_module: @my_module
    )
    init_gui
    session[:return_to] ||= request.referer
  end

  def create
    @um = UserMyModule.new(um_params.merge(my_module: @my_module))
    @um.assigned_by = current_user
    if @um.save
      flash_success = t(
        "user_my_modules.create.success_flash",
        user: @um.user.full_name,
        module: @um.my_module.name)

      # Create activity
      message = t(
        "activities.assign_user_to_module",
        assigned_user: @um.user.full_name,
        module: @my_module.name,
        assigned_by_user: current_user.full_name
      )
      Activity.create(
        user: current_user,
        project: @um.my_module.project,
        my_module: @um.my_module,
        message: message,
        type_of: :assign_user_to_module
      )
      respond_to do |format|
        format.html {
          flash[:success] = flash_success
          redirect_to session.delete(:return_to)
        }
        format.json {
          redirect_to :action => :index_edit, :format => :json
        }
      end
    else
      flash_error = t("user_my_modules.create.error_flash",
        user: @um.user.full_name,
        module: @um.my_module.name)

      respond_to do |format|
        format.html {
          flash[:error] = flash_error
          init_gui
          render :new
        }
        format.json {
          render :json => {
            :errors => [
              flash_error]
          }
        }
      end
    end
  end

  def destroy
    session[:return_to] ||= request.referer

    if @um.destroy
      flash_success = t(
        "user_my_modules.destroy.success_flash",
        user: @um.user.full_name,
        module: @um.my_module.name)

      # Create activity
      message = t(
        "activities.unassign_user_from_module",
        unassigned_user: @um.user.full_name,
        module: @my_module.name,
        unassigned_by_user: current_user.full_name
      )

      Activity.create(
        user: current_user,
        project: @um.my_module.project,
        my_module: @um.my_module,
        message: message,
        type_of: :unassign_user_from_module
      )

      respond_to do |format|
        format.html {
          flash[:success] = flash_success
          redirect_to session.delete(:return_to), :status => 303
        }
        format.json {
          redirect_to my_module_users_edit_path(format: :json), :status => 303
        }
      end
    else
      flash_error = t("user_my_modules.destroy.error_flash",
        user: @um.user.full_name,
        module: @um.my_module.name)

      respond_to do |format|
        format.html {
          flash[:error] = flash_error
          init_gui
          render :new
        }
        format.json {
          render :json => {
            :errors => [
              flash_error
            ]
          }
        }
      end
    end
  end

  private

  def load_vars
    @my_module = MyModule.find_by_id(params[:my_module_id])

    if @my_module
      @project = @my_module.project
    else
      render_404
    end

    if action_name == "destroy"
      @um = UserMyModule.find_by_id(params[:id])
      unless @um
        render_404
      end
    end
  end

  def check_view_permissions
    unless can_view_module_users(@my_module)
      render_403
    end
  end

  def check_edit_permissions
    unless can_edit_users_on_module(@my_module)
      render_403
    end
  end

  def check_create_permissions
    unless can_add_user_to_module(@my_module)
      render_403
    end
  end

  def check_delete_permisisons
    unless can_remove_user_from_module(@my_module)
      render_403
    end
  end

  def init_gui
    @users = @my_module.unassigned_users
  end

  def um_params
    params.require(:user_my_module).permit(:user_id, :my_module_id)
  end
end
