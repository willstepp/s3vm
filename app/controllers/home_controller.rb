require 'zipruby'
  
class HomeController < ApplicationController
  before_filter :login_required, :except => [:index, :login]

  def index
  end
  
  def login
    #todo: store this data in a more secure way than session
    session[:access_key_id] = params[:access_key]
    session[:secret_access_key] = params[:secret_key]
      
    redirect_to :controller => :home, :action => :buckets
  end
  
  def logout
    session[:access_key_id] = nil
    session[:secret_access_key] = nil
    
    redirect_to root_path
  end
  
  def buckets
    #get list of bucket names
    @buckets = AWS::S3.new(:access_key_id => session[:access_key_id], 
                           :secret_access_key => session[:secret_access_key]).buckets.map(&:name).to_a
  end
  
  def bucket
    @path = (params[:path].nil? or params[:path] == "/") ? nil : params[:path]
    @bucket = AWS::S3.new(:access_key_id => session[:access_key_id], 
                          :secret_access_key => session[:secret_access_key]).buckets[params[:name]]
    @parent = get_parent_dir @path
    @dirs = @bucket.as_tree(:prefix => @path).children.select(&:branch?).collect(&:prefix)
    @files = @bucket.as_tree(:prefix => @path).children.select(&:leaf?).collect(&:key)
  end
  
  def file
    @file = AWS::S3.new(:access_key_id => session[:access_key_id], 
                        :secret_access_key => session[:secret_access_key]).buckets[params[:bucket]].objects[params[:name]]
    @bucket = params[:bucket]
    @parent = get_parent_dir @file.key
    @versions = @file.versions
  end
  
  def restore
    #create new version of file
    @new_file = AWS::S3.new(:access_key_id => session[:access_key_id], 
                            :secret_access_key => session[:secret_access_key]).buckets[params[:bucket]].objects[params[:key]]
    
    #write restored data into it
    @new_file.write(@new_file.versions[params[:version_id]].read)
    
    flash[:message] = "file restored"
    redirect_to :controller => :home, :action => :file, :bucket => params[:bucket], :name => params[:key]
  end
  
  def download
    @file = AWS::S3.new(:access_key_id => session[:access_key_id], 
                        :secret_access_key => session[:secret_access_key]).buckets[params[:bucket]].objects[params[:key]]
    send_data(@file.versions[params[:version_id]].read, :filename => File.basename(params[:key]))
  end
  
  def archive
    tmp_name = "#{params[:bucket]}-#{Time.now.strftime('%Y%m%d%H%M%S')}"
    
    #download to server all files from S3
    @archive_list = AWS::S3.new(:access_key_id => session[:access_key_id], 
                                :secret_access_key => session[:secret_access_key]).buckets[params[:bucket]].objects.with_prefix(params[:path])
    @archive_list.each do |a|
      dir_path = File.dirname(a.key)
      dir_path = (dir_path == ".") ? "" : dir_path
      new_path = Rails.root.join(File.join("tmp", tmp_name), dir_path)
      FileUtils.mkpath(new_path)
      File.open(File.join(new_path, File.basename(a.key)), 'wb') {|f| f.write(a.read) }
    end
    
    #zip em up
    Zip::Archive.open("#{Rails.root.join("tmp", tmp_name)}.zip", Zip::CREATE) do |ar|
      Dir.glob("#{Rails.root.join("tmp", tmp_name)}/**/*").each do |path|
       if path.include? tmp_name
       if File.directory?(path)
          ar.add_dir(path.slice(path.index(tmp_name), path.length))
       else
          #add_file(<entry name>, <source path>)
          ar.add_file(path.slice(path.index(tmp_name), path.length), path)
       end
       end
      end
    end
    
    #send zip to user
    send_data(File.read("#{Rails.root.join("tmp", tmp_name)}.zip"), 
              :filename => "#{tmp_name}.zip")
              
    #todo: notify some process that these files need cleaned up
  end
  
  def mass_restore
    restore_versions = params[:mr_versions].to_i
    count = 0
    if restore_versions > 0
      files_to_restore = AWS::S3.new(:access_key_id => session[:access_key_id], 
                                    :secret_access_key => session[:secret_access_key]).buckets[params[:mr_bucket]].objects.with_prefix(params[:mr_path])
      files_to_restore.each do |f|
        restore_index = get_restore_version_index(restore_versions, f.versions.count)
        #todo: ensure collection is sorted latest to oldest
        f.versions.each_with_index do |v, i|
          if i == restore_index and !v.latest?
            #create new version of file
            new_file = AWS::S3.new(:access_key_id => session[:access_key_id], 
                                   :secret_access_key => session[:secret_access_key]).buckets[params[:mr_bucket]].objects[v.object.key]
            #write restored data into it
            new_file.write(v.read)
            count += 1
          end
        end
      end
    end
    
    flash[:message] = "#{count} file(s) restored"
    redirect_to :controller => :home, :action => :bucket, 
                :name => params[:mr_bucket], :path => params[:mr_path].empty? ? "/" : params[:mr_path]
  end
  
private

  def get_parent_dir(child_dir)
    if child_dir.nil? then return nil end
      
    s = child_dir.split(File::Separator)
    s.slice!(s.length-1, 1)
    pd = File.join(s)
    return pd.empty? ? "/" : pd
  end
  
  def get_restore_version_index(restore_versions, versions_count)
    #use info to calculate which version to restore
    if restore_versions >= versions_count
      return restore_versions == 1 ? -1 : versions_count-1 #last index
    elsif restore_versions < versions_count
      return restore_versions
    end
  end

  def login_required
    if session[:access_key_id].nil? or session[:secret_access_key].nil?
      redirect_to root_path
    end
  end
  
end
