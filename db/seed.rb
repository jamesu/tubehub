admin = User.create!(:name => 'admin', :password => 'password', :password_confirm => 'password')
channel = Channel.create!(:name => 'Welcome to TubeHub', :user_id => admin.id)


# Initial video
info = {:video_id => '1jJsYbVBnaE', :time => 0, :provider => 'youtube'}
video = channel.add_video(info, Time.now, :no_metadata => true)
video.update_attributes!(:title => '【MMD】With pleasant companions『Go!Go!Carlito!』【PV】', :duration => 201)
