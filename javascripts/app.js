(function() {
    Tube = {
        api: 1,

        video: null,
        admin: false,
        connected: false,
        connectionAttempts: 0,
        provider: null,
        handlers: {}, // Video handlers
        userList: {}, // Quick hash lookup for user ids

        channel: null,
        user: null,
        playlist: null
    };

    // Models
    var TubeUser = Backbone.Model.extend({
    });

    var TubeVideo = Backbone.Model.extend({
    });

    var TubeChannel = Backbone.Model.extend({
    });

    // Collections

    var TubeUsers = Backbone.Collection.extend({
       model: TubeUser,

       comparator: function(user) {
          return user.get('name')
       }
    });

    var TubePlaylist = Backbone.Collection.extend({
       model: TubeVideo,

       comparator: function(video) {
          return video.get('position')
       }
    });

    var TubeUserItem = Backbone.View.extend({
	  tagName: 'li',

	  className: 'user',

	  events: {
	    'click .title':   'open'
	  },
	
	  open: function() {
		if (this.model.get('id') == Tube.user.get('id')) {
			// Edit
			//inner.
			
		}
	  },

	  render: function() {
		var el = $(this.el).empty();
		var item = this.model;
		
		var inner = el.append('<div class="name"></div>').children().last();
		
		if (item.anon)
			el.addClass('anon');
		else
			el.addClass('auth');
		
		inner.text(item.get('name'));
		
		return this;
	  }

	});

    var TubeListItem = Backbone.View.extend({
	  tagName: 'div',

	  className: 'item',

	  events: {
	    'click .title':   'open',
	    'click .delete': 'destroy'
	  },
	
	  open: function() {
		console.log(this.model)
		$.ajax({	
	            type: 'PUT',
	            url: '/video',
	            data: {'channel_id': Tube.channel.get('id'), 'id': this.model.get('id')},
	            success: function(data) {
	                console.log('VIDEO SET',data);
	            }});
	  },
	
	  destroy: function() {
		// Delete model
		$.ajax({type: 'DELETE',
	            url: '/video',
	            data: {'channel_id': Tube.channel.get('id'), 'id': this.model.get('id')},
	            success: function(data) {
	                console.log('VIDEO DELETED',data);
	            }});
	  },

	  render: function() {
		var el = $(this.el).empty();
		var item = this.model;
		var inner = el;
		inner.append('<div class=\'time\'></div>');
		inner.append('<div class=\'title\'></div>');
		
		if (Tube.admin)
			inner.append('<div class=\'delete\'>[X]</div>');
		
		inner.append('<div class=\'clear\'></div>');
		
		console.log('tpl add', item);
		inner.attr('id', 'playlist_video_' + item.id)
		     .attr('position', item.get('position'))
		     .attr('video_id', item.get('id'));
		inner.children('.title').text(item.get('title'));
		inner.children('.time').text(Tube.parseDuration(item.get('duration')));
	
		return this;
	  }

	});
	
	
	// Init collections
	Tube.channel = new TubeChannel();
    Tube.users = new TubeUsers();
	Tube.playlist = new TubePlaylist();
	
	
	// Bind events
	
	// Channel
	Tube.channel.bind('change', function(channel){
		// ...
	})
	
	// User list
	Tube.users.bind('add', function(user){
		console.log('user add callback', user.get('id'));
		
		// Add to the list
		//if (user.get('id') != Tube.user.get('id')) {
			var item = new TubeUserItem({model: user, id:'list_' + user.get('id')});
			$('#userList').append(item.render().el);
		
			user.bind('change', function(model){ item.render() });
		//}
	});
	
	Tube.users.bind('refresh', function(err) { console.log('USER REFRESH',err);});
	
	Tube.users.bind('remove', function(user){
		var item = $('#list_' + user.get('id'));
		user.unbind();
		delete Tube.userList[user.get('id')];
		item.remove();
	});
	
	// Playlist
	Tube.playlist.bind('add', function(video){
		console.log('add callback', video.get('url'));
		var item = new TubeListItem({model: video, id:'playlist_video_' + video.get('id')});
		$('#playlist').append(item.render().el);
		
		video.bind('change', function(model){ item.renderAndSort() });
		video.bind('change:position', function(model) {
			
			var idx = Tube.playlist.indexOf(model);
			var rest = Tube.playlist.rest(idx);
			var next = rest[0];
			
			if (next) {
				// Before the next element
				item.el.insertBefore('#playlist_video_' + next.get('id'));
			} else {
				// At the end
				$('#playlist').append(item);
			}
		})
	});
	
	Tube.playlist.bind('remove', function(video){
		var item = $('#playlist_video_' + video.get('id'));
		item.unbind();
		item.remove();
	});
	

    // Controller
    Tube.registerHandler = function(provider, handler) {
		Tube.handlers[provider] = handler;
    };
    Tube.setChannel = function(channel) {
       if (Tube.channel)
          Tube.channel.unbind();
       Tube.channel = new TubeChannel(channel);

       // Connect if possible
       if (!Tube.connected)
          Tube.connect();
    };
    Tube.setTime = function(newTime) {
        if (this.video) {
            this.offsetTime = (new Date()) - newTime;
            this.video.seek(newTime);
        }
    };
    Tube.setVideo = function(id, startTime, provider, force) {
        if (this.video == null || this.video.provider != provider) {
            if (this.video) {
                this.video.stop();
            }
            this.video = null;
        }
        if (!this.video) {
            var handler = Tube.handlers[provider];
            if (handler) {
               this.video = new handler();
            } else {
				return;
			}
        }
        this.video.setVideo(id, startTime, force);
        this.offsetTime = (new Date()) - startTime;
    };
    Tube.onTimeChange = function(newTime) {
        Tube.socket.sendJSON({
            't': 'video_time',
            'channel_id': Tube.channel.get('id'),
            'time': newTime
        });
    };
    Tube.onNewVideo = function(url, time) {
      Tube.socket.sendJSON({'t': 'video', 'url': url, 'time': time, 'channel_id': Tube.channel.get('id'), 'provider': this.video.provider});
    };
    Tube.onVideoFinished = function() {
      Tube.socket.sendJSON({'t': 'video_finished', 'channel_id': Tube.channel.get('id')});
    };
    Tube.parseDuration = function(time) {
      var calc = time;
      var minutes = Math.floor(time / 60.0);
      var seconds = time % 60;
      return minutes + ':' + seconds;
    };
    Tube.addPlaylistItem = function(item) {
      var existing = Tube.playlist.get(item.id);
      if (existing)
        existing.set(item);
      else
        Tube.playlist.add(item);
    };
    Tube.removePlaylistItem = function(item) {
      Tube.playlist.remove(item.id);
    };
    Tube.connect = function() {
        Tube.setStatus('info', 'Connecting...');
        Tube.connected = true;

        Tube.socket = new WebSocket('ws://' + document.location.host + '/ws');
        Tube.socket.sendJSON = function(data) {
            Tube.socket.send(JSON.stringify(data));
        };
        Tube.socket.sendMessage = function(content) {
            Tube.socket.sendJSON({'t': 'message', 'channel_id': Tube.channel.get('id'), 'content': content});
        };
        Tube.pickColor = function(){
          var pick = ['red', 'green', 'blue', 'white', 'yellow'];
          return pick[Math.floor(Math.random()*pick.length)];
        };
        Tube.socket.onmessage = function(evt) {
            var message = JSON.parse(evt.data);
			console.log(message);
            //$('#debug').append('<p>' + evt.data + '</p>');

            if (message.t == 'hello') {
                Tube.socket.onauthenticated(message);
            } else if (message.t == 'goaway') {
                Tube.socket.onauthfailed(message);
			} else if (message.t == 'userjoined') {
				var user = Tube.users.get(message.user.id);
				if (user)
					Tube.users.remove(message.user.id);
				Tube.users.add(message.user);
				user = Tube.users.get(message.user.id);
                if (Tube.user.get('id') == message.user.id) {
                    Tube.admin = (message['scope'] || []).indexOf('admin') >= 0;

					// TODO: use the binding to update this
					$('#playlistContainer').addClass('editable');
                }
                Tube.userList[message.user.id] = user;
            } else if (message.t == 'userleft') {
                Tube.users.remove(message.user.id);
            } else if (message.t == 'usermod') {
                var oldName = Tube.userList[message.user.id].get('name');
                Tube.userList[message.user.id].set(message.user);
                if (message.user.name) // TODO: see if we can use backbone for this
                   Tube.chat.onchangename(message.user.id, oldName);
            } else if (message.t == 'message') {
				Tube.chat.onmessage(message.uid, message.content);
            } else if (message.t == 'playlist_video') {
                Tube.addPlaylistItem(message);
            } else if (message.t == 'playlist_video_removed') {
                Tube.removePlaylistItem(message);
            } else if (message.t == 'video') {
                if (!Tube.admin || Tube.video == null || message.force) {
                    Tube.setVideo(message.url, message.time, message.provider, message.force);
                }
            } else if (message.t == 'video_time') {
                // Set the time of the video, ignoring minor offsets
                if (!Tube.admin && Tube.video && Tube.video.control) {
                    var currentTime = Tube.video.currentTime();
                    if ((message.time - currentTime < -Tube.video.timeMargin) || (message.time - currentTime > Tube.video.timeMargin)) {
                        //console.log('Adjust offset:', message.time - currentTime);
                        Tube.setTime(message.time);
                    }
                }
            }
        };
        Tube.socket.onerror = function() {
	       this.onclose();
        };
        Tube.socket.onclose = function() {
			Tube.users.reset();
            Tube.userList = {};
            if (Tube.connected) {
              // Connection failed, retry
              if (Tube.connectionAttempts > 10) {
                 Tube.setStatus('critical', 'Server down, try again later');
	          } else {
                 Tube.setStatus('warning', 'Connection failed, retrying...');
                 Tube.connectTimer = setTimeout(function(){ Tube.connectionAttempts += 1; Tube.connect(); }, 4000+(Math.random()*1000));
              }
            } else {
               Tube.connectionAttempts = 0;
            }
        };
        Tube.socket.onopen = function() {
            Tube.admin = false;

            // Tie the user with the websocket
            $.ajax({
                type: 'POST',
                url: '/auth/socket_token',
                success: function(data) {
                    Tube.socket.sendJSON({
                        't': 'auth',
                        'auth_token': data.auth_token
                    });
                },
                error: function(xhr, status, error) {
                    //console.log('BARF', status, error);
                    Tube.socket.close();
                }
            });
        };
        Tube.socket.onauthenticated = function(message) {
            // Verify we are using the correct version
	        if (message.api != Tube.api) {
	           window.location.reload();
	           return;
            }
            if (Tube.user)
               Tube.user.unbind();
	        Tube.user = new TubeUser(message.user);
	        Tube.user.bind('change', function(){ console.log('WE CHANGED?!', this); });
            Tube.socket.sendJSON({
                't': 'subscribe',
                'channel_id': Tube.channel.get('id')
            });
            Tube.clearStatus();
        };
        Tube.socket.onauthfailed = function(message) {
           if (message.reason == 'banned') {
				Tube.setStatus('critical', 'You are banned from this channel');
			} else {
				Tube.setStatus('critical', 'Authorization failed');
				console.log('OTHER REASON AUTH FAILED:', message);
			}
			
			Tube.connected = false;
			Tube.socket.close();
		};
    };
    Tube.disconnect = function() {
        Tube.connected = false;
        Tube.socket.disconnect();
        Tube.socket = null;
    };

    Tube.setStatus = function(code, message) {
       $('#status').attr('class', code).text(message);
    };
    
    Tube.clearStatus = function() {
       $('#status').attr('class', '');
    };
})();

// Entry
$(document).ready(function() {
    if (!$('#video'))
    return;

    $('#messageEntryBox').keypress(function(evt){
      if (evt.keyCode == 13) {
        if (evt.target.value.indexOf('/nick') == 0) {
          var newName = evt.target.value.split(' ')[1];
          if (newName)
            Tube.socket.sendJSON({'t': 'usermod', 'name': newName, 'channel_id': Tube.channel.get('id')});
        } else {
          Tube.socket.sendMessage(evt.target.value);
        }
        evt.target.value = '';
      }
    })

    $('#playlistEntryBox').keypress(function(evt){
      if (evt.keyCode == 13) {
      $.ajax({	
            type: 'POST',
            url: '/video',
            data: {'uid': Tube.user.get('id'), 'channel_id': Tube.channel.get('id'), 'url': evt.target.value},
            success: function(data) {
                console.log('VIDEO ADDED',data);
            }});
        evt.target.value = '';
      }
    });

});
