class Asset < ActiveRecord::Base
  include SearchableModel
  include DatabaseHelper

  require 'tempfile'

  # Paperclip validation
  has_attached_file :file, {
    styles: {
      medium: '300x300>'
    }
  }

  validates_attachment :file, presence: true, size: { less_than: 50.megabytes }
  validates :estimated_size, presence: true
  validates :file_present, inclusion: { in: [true, false] }

  # Should be checked for any security leaks
  do_not_validate_attachment_file_type :file

  before_file_post_process :allow_styles_on_images

  # Asset validation
  # This could cause some problems if you create empty asset and want to
  # assign it to result
  validate :step_or_result

  belongs_to :created_by, foreign_key: 'created_by_id', class_name: 'User'
  belongs_to :last_modified_by, foreign_key: 'last_modified_by_id', class_name: 'User'
  has_one :step_asset,
    inverse_of: :asset,
    dependent: :destroy
  has_one :step, through: :step_asset,
    dependent: :nullify

  has_one :result_asset,
    inverse_of: :asset,
    dependent: :destroy
  has_one :result, through: :result_asset,
    dependent: :nullify
  has_many :report_elements, inverse_of: :asset, dependent: :destroy
  has_one :asset_text_datum, inverse_of: :asset, dependent: :destroy

  def file_empty(name, size)
    file_ext = name.split(".").last
    self.file_file_name = name
    self.file_content_type = Rack::Mime.mime_type(".#{file_ext}")
    self.file_file_size = size
    self.file_updated_at = DateTime.now
    self.file_present = false
  end

  def self.new_empty(name, size)
    asset = self.new
    asset.file_empty name, size
    asset
  end

  def self.search(
    user,
    include_archived,
    query = nil,
    page = 1
  )
    step_ids =
      Step
      .search(user, include_archived, nil, SHOW_ALL_RESULTS)
      .joins(:step_assets)
      .select("step_assets.id")
      .distinct

    result_ids =
      Result
      .search(user, include_archived, nil, SHOW_ALL_RESULTS)
      .joins(:result_asset)
      .select("result_assets.id")
      .distinct

    new_query = Asset
      .distinct
      .joins("LEFT OUTER JOIN step_assets ON step_assets.asset_id = assets.id")
      .joins("LEFT OUTER JOIN result_assets ON result_assets.asset_id = assets.id")
      .where(
        "step_assets.id IN (?) OR result_assets.id IN (?)",
        step_ids,
        result_ids
      )
      .where_attributes_like(:file_file_name, query)

    # Show all results if needed
    if page == SHOW_ALL_RESULTS
      new_query
    else
      new_query
        .limit(SEARCH_LIMIT)
        .offset((page - 1) * SEARCH_LIMIT)
    end
  end

  def is_image?
    !(self.file.content_type =~ /^image/).nil?
  end
  # TODO: get the current_user
  # before_save do
  #   if current_user
  #     self.created_by ||= current_user
  #     self.last_modified_by = current_user if self.changed?
  #   end
  # end

  def is_stored_on_s3?
    file.options[:storage].to_sym == :s3
  end

  def post_process_file(org = nil)
    # Update self.empty
    self.update(file_present: true)

    # Extract asset text if it's of correct type
    if TEXT_EXTRACT_FILE_TYPES.any? { |v| file_content_type.start_with? v }
      Rails.logger.info "Asset #{id}: Creating extract text job"
      # The extract_asset_text also includes
      # estimated size calculation
      delay(queue: :assets).extract_asset_text(org)
    else
      # Update asset's estimated size immediately
      update_estimated_size(org)
    end
  end

  def extract_asset_text(org = nil)
    if file.blank?
      return
    end

    begin
      file_path = file.path

      if file.is_stored_on_s3?
        fa = file.fetch
        file_path = fa.path
      end

      y = Yomu.new file_path
      text_data = y.text

      if asset_text_datum.present?
        # Update existing text datum if it exists
        asset_text_datum.update(data: text_data)
      else
        # Create new text datum
        AssetTextDatum.create(data: text_data, asset: self)
      end

      Rails.logger.info "Asset #{id}: Asset file successfully extracted"

      # Finally, update asset's estimated size to include
      # the data vector
      update_estimated_size(org)
    rescue Exception => e
      Rails.logger.fatal "Asset #{id}: Error extracting contents from asset file #{file.path}: " + e.message
    ensure
      File.delete file_path if fa
    end
  end

  # If organization is provided, its space_taken
  # is updated as well
  def update_estimated_size(org = nil)
    if file_file_size.blank?
      return
    end

    es = file_file_size
    if asset_text_datum.present? and asset_text_datum.persisted? then
      asset_text_datum.reload
      es += get_octet_length_record(asset_text_datum, :data)
      es += get_octet_length_record(asset_text_datum, :data_vector)
    end
    es = es * ASSET_ESTIMATED_SIZE_FACTOR
    update(estimated_size: es)
    Rails.logger.info "Asset #{id}: Estimated size successfully calculated"

    # Finally, update organization's space
    if org.present?
      org.take_space(es)
      org.save
    end
  end

  def presigned_url
    if file.is_stored_on_s3?
      signer = Aws::S3::Presigner.new(client: S3_BUCKET.client)

      signer.presigned_url(:get_object,
        bucket: S3_BUCKET.name,
        key: file.path[1..-1],
        expires_in: 30,
        # this response header forces object download
        response_content_disposition: 'attachment; filename=' + file_file_name)
    end
  end

  protected

  # Checks if attachments is an image (in post processing imagemagick will
  # generate styles)
  def allow_styles_on_images
    if !(file.content_type =~ %r{^(image|(x-)?application)/(x-png|pjpeg|jpeg|jpg|png|gif)$})
      return false
    end
  end

  private

  def file_changed?
    previous_changes.present? and
    (
      (
        previous_changes.key? "file_file_name" and
        previous_changes["file_file_name"].first !=
          previous_changes["file_file_name"].last
      ) or (
        previous_changes.key? "file_file_size" and
        previous_changes["file_file_size"].first !=
          previous_changes["file_file_size"].last
      )
    )
  end

  def step_or_result
    # We must allow both step and result to be blank because of GUI
    # (eventhough it's not really a "valid" asset)
    if step.present? && result.present?
      errors.add(:base, "Asset can only be result or step, not both.")
    end
  end

end
