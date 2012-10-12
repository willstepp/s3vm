S3FileManager::Application.routes.draw do
  match 'login' => 'home#login', :via => :post, :as => :login
  match 'logout' => 'home#logout', :via => :get, :as => :logout
  
  match 'buckets' => 'home#buckets', :via => :get
  match 'bucket' => 'home#bucket', :via => :get
  match 'file' => 'home#file', :via => :get
  
  match 'restore' => 'home#restore', :via => :get
  match 'download' => 'home#download', :via => :get
  match 'archive' => 'home#archive', :via => :get
  match 'mass_restore' => 'home#mass_restore', :via => :post

  root :to => "home#index"
end
