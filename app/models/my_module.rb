class MyModule < ActiveRecord::Base
  include ArchivableModel, SearchableModel


  validates :name,
    presence: true,
    length: { minimum: 2, maximum: 50 }
  validates :x, :y, :workflow_order, presence: true
  validates :project, presence: true
  validates :my_module_group, presence: true, if: "!my_module_group_id.nil?"

  belongs_to :created_by, foreign_key: 'created_by_id', class_name: 'User'
  belongs_to :last_modified_by, foreign_key: 'last_modified_by_id', class_name: 'User'
  belongs_to :archived_by, foreign_key: 'archived_by_id', class_name: 'User'
  belongs_to :restored_by, foreign_key: 'restored_by_id', class_name: 'User'
  belongs_to :project, inverse_of: :my_modules
  belongs_to :my_module_group, inverse_of: :my_modules
  has_many :steps, inverse_of: :my_module, :dependent => :destroy
  has_many :results, inverse_of: :my_module, :dependent => :destroy
  has_many :my_module_tags, inverse_of: :my_module, :dependent => :destroy
  has_many :tags, through: :my_module_tags
  has_many :my_module_comments, inverse_of: :my_module, :dependent => :destroy
  has_many :comments, through: :my_module_comments
  has_many :inputs, :class_name => 'Connection', :foreign_key => "input_id", inverse_of: :to, :dependent => :destroy
  has_many :outputs, :class_name => 'Connection', :foreign_key => "output_id", inverse_of: :from, :dependent => :destroy
  has_many :my_modules, through: :outputs, source: :to
  has_many :my_module_antecessors, through: :inputs, source: :from, class_name: 'MyModule'
  has_many :sample_my_modules, inverse_of: :my_module, :dependent => :destroy
  has_many :samples, through: :sample_my_modules
  has_many :user_my_modules, inverse_of: :my_module, :dependent => :destroy
  has_many :users, through: :user_my_modules
  has_many :activities, inverse_of: :my_module
  has_many :report_elements, inverse_of: :my_module, :dependent => :destroy

  def self.search(user, include_archived, query = nil, page = 1)
    project_ids =
      Project
      .search(user, include_archived, nil, SHOW_ALL_RESULTS)
      .select("id")

    if include_archived
      new_query = MyModule
        .distinct
        .where("my_modules.project_id IN (?)", project_ids)
        .where_attributes_like(:name, query)
    else
      new_query = MyModule
        .distinct
        .where("my_modules.project_id IN (?)", project_ids)
        .where("my_modules.archived = ?", false)
        .where_attributes_like(:name, query)
    end

    # Show all results if needed
    if page == SHOW_ALL_RESULTS
      new_query
    else
      new_query
        .limit(SEARCH_LIMIT)
        .offset((page - 1) * SEARCH_LIMIT)
    end
  end

  # Deep-clone given array of assets
  def self.deep_clone_assets(assets_to_clone, org)
    assets_to_clone.each do |src_id, dest_id|
      src = Asset.find_by_id(src_id)
      dest = Asset.find_by_id(dest_id)
      if src.present? and dest.present? then
        # Clone file
        dest.file = src.file
        dest.save

        # Clone extracted text data if it exists
        if (atd = src.asset_text_datum).present? then
          atd2 = AssetTextDatum.new(
            data: atd.data,
            asset: dest
          )
          atd2.save
        end

        # Update estimated size of cloned asset
        dest.update(estimated_size: src.estimated_size)

        # Update organization's space taken
        org.reload
        org.take_space(dest.estimated_size)
        org.save
      end
    end
  end

  # Removes assigned samples from module and connections with other
  # modules.
  def archive (current_user)
    self.x = 0
    self.y = 0
    # Remove association with module group.
    self.my_module_group = nil

    MyModule.transaction do
      archived = super
      # Unassociate all samples from module.
      archived = SampleMyModule.destroy_all(:my_module => self) if archived
      # Remove all connection between modules.
      archived = Connection.delete_all(:input_id => id) if archived
      archived = Connection.delete_all(:output_id => id) if archived
      unless archived
        raise ActiveRecord::Rollback
      end
    end
    archived
  end

  # Similar as super restore, but also calculate new module position
  def restore(current_user)
    restored = false

    # Calculate new module position
    new_pos = get_new_position
    self.x = new_pos[:x]
    self.y = new_pos[:y]

    MyModule.transaction do
      restored = super

      unless restored
        raise ActiveRecord::Rollback
      end
    end
    restored
  end

  def unassigned_users
    User.find_by_sql(
      "SELECT DISTINCT users.id, users.full_name FROM users " +
      "INNER JOIN user_projects ON users.id = user_projects.user_id " +
      "WHERE user_projects.project_id = #{project_id.to_s}" +
      " AND users.id NOT IN " +
      "(SELECT DISTINCT user_id FROM user_my_modules WHERE user_my_modules.my_module_id = #{id.to_s})"
    )
  end

  def unassigned_samples
    Sample.where(organization_id: project.organization).where.not(id: samples)
  end

  def unassigned_tags
    Tag.find_by_sql(
      "SELECT DISTINCT tags.id, tags.name, tags.color FROM tags " +
      "WHERE tags.project_id = #{project_id.to_s} AND tags.id NOT IN " +
      "(SELECT DISTINCT tag_id FROM my_module_tags WHERE my_module_tags.my_module_id = #{id.to_s})"
      )
  end

  def number_of_steps
    steps.count
  end

  def last_activities(count = 20)
    Activity.where(my_module_id: id).order(:created_at).last(count)
  end

  # Get module comments ordered by created_at time. Results are paginated
  # using last comment id and per_page parameters.
  def last_comments(last_id = 1, per_page = 20)
    last_id = 9999999999999 if last_id <= 1
    Comment.joins(:my_module_comment)
      .where(my_module_comments: {my_module_id: id})
      .where('comments.id <  ?', last_id)
      .order(created_at: :desc)
      .limit(per_page)
  end

  def last_activities(last_id = 1, count = 20)
    last_id = 9999999999999 if last_id <= 1
    Activity.joins(:my_module)
      .where(my_module_id: id)
      .where('activities.id <  ?', last_id)
      .order(created_at: :desc)
      .limit(count)
      .uniq
  end

  def first_n_samples(count = 20)
    samples.order(name: :asc).limit(count)
  end

  def completed_steps
    steps.select { |step| step.completed }
  end

  def number_of_samples
    samples.count
  end

  def is_overdue?(datetime = DateTime.current)
    due_date.present? and datetime.utc > due_date.utc
  end

  def overdue_for_days(datetime = DateTime.current)
    if due_date.blank? or due_date.utc > datetime.utc
      return 0
    else
      return ((datetime.utc.to_i - due_date.utc.to_i) / (60*60*24).to_f).ceil
    end
  end

  def is_one_day_prior?(datetime = DateTime.current)
    is_due_in?(datetime, 1.day)
  end

  def is_due_in?(datetime, diff)
    due_date.present? and datetime.utc < due_date.utc and datetime.utc > (due_date.utc - diff)
  end

  def space_taken
    st = 0
    steps.find_each do |step|
      st += step.space_taken
    end
    results
    .includes(:result_asset)
    .find_each do |result|
      st += result.space_taken
    end
    st
  end

  def archived_results
    results
    .select('results.*')
    .select('ra.id AS result_asset_id')
    .select('rt.id AS result_table_id')
    .select('rx.id AS result_text_id')
    .joins('LEFT JOIN result_assets AS ra ON ra.result_id = results.id')
    .joins('LEFT JOIN result_tables AS rt ON rt.result_id = results.id')
    .joins('LEFT JOIN result_texts AS rx ON rx.result_id = results.id')
    .where(:archived => true)
  end

  # Treat this module as root, get all modules of that subtree
  def get_downstream_modules
    final = []
    modules = [self]
    while !modules.empty?
      my_module = modules.shift
      if !final.include?(my_module)
        final << my_module
      end
      modules.push(*my_module.my_modules.flatten)
    end
    final
  end

  # Treat this module as inversed root, get all modules of that inversed subtree
  def get_upstream_modules
    final = []
    modules = [self]
    while !modules.empty?
      my_module = modules.shift
      if !final.include?(my_module)
        final << my_module
      end
      modules.push(*my_module.my_module_antecessors.flatten)
    end
    final
  end


  # Generate the samples belonging to this module
  # in JSON form, suitable for display in handsontable.js
  def samples_json_hot(order)
    data = []
    samples.order(created_at: order).each do |sample|
      sample_json = []
      sample_json << sample.name
      if sample.sample_type.present?
        sample_json << sample.sample_type.name
      else
        sample_json << I18n.t("samples.table.no_type")
      end
      if sample.sample_group.present?
        sample_json << sample.sample_group.name
      else
        sample_json << I18n.t("samples.table.no_group")
      end
      sample_json << I18n.l(sample.created_at, format: :full)
      sample_json << sample.user.full_name
      data << sample_json
    end

    # Prepare column headers
    headers = [
      I18n.t("samples.table.sample_name"),
      I18n.t("samples.table.sample_type"),
      I18n.t("samples.table.sample_group"),
      I18n.t("samples.table.added_on"),
      I18n.t("samples.table.added_by")
    ]
    { data: data, headers: headers }
  end

  def deep_clone(current_user)
    assets_to_clone = []

    # Copy the module
    clone = MyModule.new(
      name: self.name,
      project: self.project,
      description: self.description,
      x: self.x,
      y: self.y)
    clone.save

    # Copy steps
    self.steps.each do |step|
      step2 = Step.new(
        name: step.name,
        description: step.description,
        position: step.position,
        completed: false,
        user: current_user,
        my_module: clone)
      step2.save

      # Copy checklists
      step.checklists.each do |checklist|
        checklist2 = Checklist.new(
          name: checklist.name,
          step: step2
          )
        checklist2.created_by = current_user
        checklist2.last_modified_by = current_user
        checklist2.save

        checklist.checklist_items.each do |item|
          item2 = ChecklistItem.new(
            text: item.text,
            checked: false,
            checklist: checklist2)
          item2.created_by = current_user
          item2.last_modified_by = current_user
          item2.save
        end

        step2.checklists << checklist2
      end

      # "Shallow" Copy assets
      step.assets.each do |asset|
        asset2 = Asset.new_empty(
          asset.file_file_name,
          asset.file_file_size
        )
        asset2.created_by = current_user
        asset2.last_modified_by = current_user
        asset2.save

        step2.assets << asset2
        assets_to_clone << [asset.id, asset2.id]
      end

      # Copy tables
      step.tables.each do |table|
        table2 = Table.new(
          contents: table.contents)
        table2.created_by = current_user
        table2.last_modified_by = current_user
        step2.tables << table2
      end
    end

    # Call clone module helper
    MyModule.delay(queue: :assets).deep_clone_assets(
      assets_to_clone,
      self.project.organization
    )

    clone.reload

    return clone
  end

  # Writes to user log.
  def log(message)
    final = "[%s] %s" % [name, message]
    project.log(final)
  end

  private

  # Find an empty position for the restored module. It's
  # basically a first empty row with x=0.
  def get_new_position
    if project.blank?
      return { x: 0, y: 0 }
    end

    new_y = 0
    positions = project.active_modules.collect{ |m| [m.x, m.y] }
    (0..10000).each do |n|
      unless positions.include? [0, n]
        new_y = n
        break
      end
    end

    return { x: 0, y: new_y }
  end

end
