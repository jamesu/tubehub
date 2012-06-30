// From http://stackoverflow.com/questions/1184624/serialize-form-to-json-with-jquery
$.fn.serializeObject = function()
{
    var o = {};
    var a = this.serializeArray();
    $.each(a, function() {
        if (o[this.name] || o[this.name] == '') {
            if (!o[this.name].push) {
                o[this.name] = [o[this.name]];
            }
            o[this.name].push(this.value || '');
        } else {
            o[this.name] = this.value || '';
        }
    });
    return o;
};

(function() {
    Tube = {
        api: 1,

        video: null,
        mod: false,
        leader: false,
        connected: false,
        connectionAttempts: 0,
        provider: null,
        handlers: {}, // Video handlers
        userList: {}, // Quick hash lookup for user ids

        channel: null,
        user: null,
        playlist: null,

        tripcode: null, // authentication tripcode
        
        Views: {},
        Models: {}
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
        
        el.attr('user_id', this.model.get('id'));

        if (item.get('anon'))
          el.addClass('anon');
        else
          el.addClass('auth');

        var name = el.append('<span class="name"></span>').children().last();
        var tripcode = el.append('<span class="trip"></span>').children().last();
        name.text(item.get('name'));
        tripcode.text(item.get('tripcode'));
        
        if (item.get('leader')) {
          el.append('<span class="lead">*</span>')
        }
        
        if (Tube.mod) {
          el.append('<a href="#" class="buttonKickUser">(K)</a>');
          el.append('<a href="#" class="buttonBanUser">(B)</a>');
        }
        return this;
      }
    });
    
    var PlaylistView = {
      tagName: 'div',
      id: 'playlist',
      
      events: {
        'click .item .title':   'openItem',
        'click .item .delete':  'destroyItem'
      }
    };
    
    PlaylistView.initialize = function(options) {
      // Playlist
      Tube.playlist.bind('add', this.addVideo, this);
      Tube.playlist.bind('change', this.updateVideo, this);
      Tube.playlist.bind('remove', this.removeVideo, this);
      Tube.playlist.bind('reset', this.addVideos, this);
    }
    
    PlaylistView.openItem = function(event) {
      if (!Tube.mod)
        return;
      var item = Tube.playlist.get($(event.target).parents('.item:first').attr('video_id'));
      if (!item)
        return;
      
      Tube.sendMessage({'t': 'video', 'video_id': item.get('id')});
    }
    
    PlaylistView.destroyItem = function(event) {
      if (!Tube.mod)
        return;
      
      var item = Tube.playlist.get($(event.target).parents('.item:first').attr('video_id'));
      if (!item)
        return;
      
      Tube.sendMessage({'t': 'del_video', 'video_id': item.get('id')});
    }
    
    PlaylistView.addVideo = function(video) {
        var item = $(this.el).append('<div class="item" id="playlist_video_' + video.get('id') + '"></div>').children().last();
        this.renderItem(video, item);
    }
    
    PlaylistView.addVideos = function(videos) {
      this.render();
      videos.each(this.addVideo, this);
    }
    
    PlaylistView.updateVideo = function(video, attrs) {
      var attrs = video.changedAttributes();
      var el = $('#playlist_video_' + video.get('id'));
      this.renderItem(video, el);
      
      Tube.playlist.sort({silent: true});
      
      if (attrs.position != undefined) {
          var idx = Tube.playlist.indexOf(video);
          var rest = Tube.playlist.rest(idx+1);
          var next = rest[0];

          if (next) {
            // Before the next element
            el.insertBefore('#playlist_video_' + next.get('id'));
          } else if (idx == 0) {
            // At the start
            $(this.el).prepend(el);
          } else {
            // At the end
            $(this.el).append(el);
          }
      }
    }
    
    PlaylistView.removeVideo = function(video) {
      var item = $('#playlist_video_' + video.get('id'));
      item.unbind();
      item.remove();
    }
    
    PlaylistView.render = function() {
      $(this.el).empty();
    }
    
    PlaylistView.renderItem = function(item, el) {
      var inner = el;
      el.empty();
      inner.append('<div class=\'time\'></div>');
      inner.append('<div class=\'title\'></div>');

      if (Tube.mod)
      inner.append('<div class=\'delete\'>[X]</div>');

      inner.append('<div class=\'clear\'></div>');

      inner.attr('id', 'playlist_video_' + item.id)
      .attr('position', item.get('position'))
      .attr('video_id', item.get('id'));
      inner.children('.title').text(item.get('title'));
      inner.children('.time').text(Tube.parseDuration(item.get('duration')));
      
      if (Tube.video_id == item.get('id'))
        el.addClass('active');

      return this;
    }
    
    Tube.Views.PlaylistView = Backbone.View.extend(PlaylistView);

    // Init collections
    Tube.channel = new TubeChannel();
    Tube.users = new TubeUsers();
    Tube.playlist = new TubePlaylist();


    // Bind events

    // Channel
    Tube.onChannelChange = function(channel, attrs) {
      // ...
      $('#tab_chan_' + channel.get('id') + ' a').text(channel.get('permalink'));
      $('#chanTitle').text(channel.get('name'));
      if (channel.get('banner'))
        $('#chanBanner').html(channel.get('banner'));
      if (channel.get('footer'))
        $('#chanFooter').html(channel.get('footer'));
      
      Tube.onChangeSkipCount(channel);
      
      if (channel.get('locked')) {
        $('#playlistEntryBox').hide();
        $('#lockButton').text('Unlock Playlist');
      } else {
        $('#playlistEntryBox').show();
        $('#lockButton').text('Lock Playlist');
      }
    }
    Tube.onChangeSkipCount = function(channel) {
      var button = $('#skipButton');
      if (button) {
        var limit = channel.get('skip_limit')||-1;
        if (limit == -1 || limit > 100) {
          button.hide();
        } else {
          button.show();
          var real_limit = Tube.users.length * (channel.get('skip_limit') / 100.0);
          button.text('Skip (' + (channel.get('skip')||0) + '/' + real_limit + ')');
        }
      }
    }

    // User list
    Tube.users.bind('add', function(user){
      // Add to the list
      //if (user.get('id') != Tube.user.get('id')) {
        var item = new TubeUserItem({model: user, id:'list_' + user.get('id')});
        $('#userList').append(item.render().el);

        user.bind('change', function(model){ item.render() });
        //}
        Tube.onUsersChanged();
    });

    Tube.users.bind('reset', function(users) { 
      $('#userList').empty();
      users.each(function(user){
          var item = new TubeUserItem({model: user, id:'list_' + user.get('id')});
          $('#userList').append(item.render().el);

          user.bind('change', function(model){ item.render() });
      });
      
      Tube.onUsersChanged();
    });

    Tube.users.bind('remove', function(user){
      var item = $('#list_' + user.get('id'));
      user.unbind();
      delete Tube.userList[user.get('id')];
      item.remove();
      Tube.onUsersChanged();
    });

    // Controller
    Tube.registerHandler = function(provider, handler) {
      Tube.handlers[provider] = handler;
    };
    Tube.setChannel = function(channel) {
       if (Tube.channel)
          Tube.channel.unbind();
       Tube.channel = new TubeChannel(channel);
       Tube.channel.bind('change', Tube.onChannelChange, Tube);

       // Connect if possible
       if (!Tube.connected)
          Tube.connect();
    };
    Tube.setTime = function(newTime) {
        if (this.video) {
            this.offsetTime = (new Date()) - (newTime*1000);
            this.video.seek(newTime);
        }
    };
    Tube.setVideo = function(opts) {
        var id = opts.id;
        var url = opts.url;
        var startTime = opts.time;
        var provider = opts.provider;
        var force = opts.force;
        
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
        this.video_id = id;
        this.video.setVideo(url, startTime, force);
        this.offsetTime = (new Date()) - (startTime*1000);
        this.onSetVideo(opts);
    };
    Tube.onSetVideo = function(video) {
      $('#videoTitle').text(video.title);
      $('#playlist .item').removeClass('active');
      
      if (video.id) {
        $('#playlist_video_' + video.id).addClass('active');
      }
    };
    Tube.onTimeChange = function(newTime) {
        if (Tube.leader) {
          var currentTime = ((new Date()) - Tube.offsetTime) / 1000.0;
          if ((newTime - currentTime < -Tube.video.timeMargin) || (newTime - currentTime > Tube.video.timeMargin)) {
            Tube.offsetTime = (new Date()) - (newTime*1000);
            Tube.sendMessage({
                't': 'video_time',
                'time': newTime
            });
          }
        } else {
          var currentTime = ((new Date()) - Tube.offsetTime) / 1000.0;
          if ((newTime - currentTime < -Tube.video.timeMargin) || (newTime - currentTime > Tube.video.timeMargin)) {
            // Verify we haven't just got to the end of the video
            if (currentTime > Tube.video.duration())
              return;
            Tube.setTime(((new Date()) - Tube.offsetTime) / 1000.0);
          }
        }
    };
    Tube.onNewVideo = function(url, time) {
      $('#videoTitle').text(url);
      if (Tube.leader)
        Tube.sendMessage({'t': 'video', 'url': url, 'time': time, 'provider': this.video.provider});
    };
    Tube.onVideoFinished = function() {
      Tube.sendMessage({'t': 'video_finished'});
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
    Tube.sendMessage = function(data) {
      Tube.socket.send(JSON.stringify(data));
    };
    Tube.sendChat = function(content) {
      Tube.sendMessage({'t': 'message', 'content': content});
    }

    Tube.messageHandlers = {
      'hello': function(msg) { Tube.onauthenticated(msg); },
      'goaway': function(msg) { Tube.onauthfailed(msg); },
      'userjoined': function(msg) {
          var user = Tube.users.get(msg.user.id);
          if (user)
            Tube.users.remove(msg.user.id);
          Tube.users.add(msg.user);
          user = Tube.users.get(msg.user.id);
          if (Tube.user.get('id') == msg.user.id) {
            Tube.mod = msg['scope'] != '';
            Tube.leader = msg['leader'] ? true : false;
            Tube.users.each(function(user){ user.trigger('change') }); // hack: update mod ui controls
            Tube.onSetupUI();
          }
          Tube.userList[msg.user.id] = user;
       },
      'userleft': function(msg) { Tube.users.remove(msg.user.id); },
      'usermod': function(msg) {
          var oldName = Tube.userList[msg.user.id].get('name');
          var oldTripcode = Tube.userList[msg.user.id].get('tripcode');
          Tube.userList[msg.user.id].set(msg.user);
          if (Tube.user.get('id') == msg.user.id) { // Tube.user is separate
            Tube.user.set(msg.user);
          }
          // Handle name changes
          if (msg.user.name && msg.user.name != oldName) {
             Tube.chat.onchangename(msg.user.id, oldName, oldTripcode);
             if (Tube.user.get('id') == msg.user.id) {
                // Remember our tripcode
                $.ajax({
                    type: 'POST',
                    contentType: 'json',
                    data: JSON.stringify({name: Tube.tripcode}),
                    url: '/auth/name'});
            }
          }
          // Handle leader changes
          if (msg.user.leader) {
             Tube.leader = Tube.user.get('id') == msg.user.id;
             Tube.chat.onchangeleader(Tube.userList[msg.user.id]);
          }
      },
      'message': function(msg) { Tube.chat.onmessage(msg.uid, msg.content); },
      'playlist_video': function(msg) { Tube.addPlaylistItem(msg); },
      'playlist_video_removed': function(msg) { Tube.removePlaylistItem(msg); },
      'video': function(msg) {
          if (!Tube.admin || Tube.video == null || msg.force) {
            Tube.setVideo(msg);
            Tube.channel.set({'skip': 0});
          }
      },
      'video_time': function(msg) {
          // Set the time of the video, ignoring minor offsets
          if (!Tube.admin && Tube.video && Tube.video.control) {
              var currentTime = Tube.video.currentTime();
              if ((msg.time - currentTime < -Tube.video.timeMargin) || (msg.time - currentTime > Tube.video.timeMargin)) {
                  //console.log('Adjust offset:', msg.time - currentTime);
                  Tube.setTime(msg.time);
              }
          }
      },
      'chanmod': function(msg) {
        if (Tube.channel.get('id') == msg.id) {
          Tube.channel.set(msg);
        }
      },
      'skip': function(msg) { Tube.channel.set({'skip': msg.count}); }
    };

    Tube.connect = function() {
        Tube.setStatus('info', 'Connecting...');
        Tube.connected = true;

        Tube.socket = new WebSocket(WEB_SOCKET_PATH);
        Tube.socket.onmessage = function(evt) {
            var message = JSON.parse(evt.data);
            //console.log(message.t,message);
            //$('#debug').append('<p>' + evt.data + '</p>');

            if (Tube.messageHandlers[message.t])
              Tube.messageHandlers[message.t](message);
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
                    Tube.sendMessage({
                        't': 'auth',
                        'auth_token': data.auth_token,
                        'name': data.name
                    });
                    Tube.tripcode = data.name;
                },
                error: function(xhr, status, error) {
                    if (error == 'Unauthorized') {
                      var name = Tube.tripcode ? Tube.tripcode : 'Anonymous'
	                    Tube.sendMessage({
	                        't': 'auth',
	                        'name': name
	                    });
                    } else {
                      Tube.socket.close();
                    }
                }
            });
        };
    };
    Tube.disconnect = function() {
        Tube.connected = false;
        Tube.socket.disconnect();
        Tube.socket = null;
    };

    Tube.onauthenticated = function(message) {
      // Verify we are using the correct version
      if (message.api != Tube.api) {
        window.location.reload();
        return;
      }
      if (Tube.user)
         Tube.user.unbind();
      Tube.user = new TubeUser(message.user);
      Tube.sendMessage({
          't': 'subscribe',
          'channel_id': Tube.channel.get('id')
      });
      
      // Remember our tripcode
      $.ajax({
          type: 'POST',
          contentType: 'json',
          data: JSON.stringify({name: Tube.tripcode}),
          url: '/auth/name'});
      Tube.clearStatus();
    };
    Tube.onauthfailed = function(message) {
       if (message.reason == 'ban') {
         Tube.setStatus('critical', 'You are banned from this channel: ' + message.comment);
       } else {
         Tube.setStatus('critical', 'Authorization failed');
         //console.log('OTHER REASON AUTH FAILED:', message);
       }
       Tube.connected = false;
       Tube.socket.close();
    };

    Tube.setStatus = function(code, message) {
       $('#status').attr('class', code).text(message);
    };
    
    Tube.clearStatus = function() {
       $('#status').attr('class', '');
    };
    Tube.setName = function(tripcode) {
      Tube.tripcode = tripcode;
      Tube.sendMessage({'t': 'usermod', 'name': tripcode});
    };
    Tube.onSetupUI = function() {
      // Basically we need to make sure all ui controls we need are shown
      if (Tube.mod)
        $('#playlistContainer').addClass('editable');
      else
        $('#playlistContainer').removeClass('editable');
      
      var toolbar = $('#userToolbar').empty();
      
      if (Tube.mod) {
        toolbar.append('<a href="#" class="button" id="leadButton">Take Lead</a>');
        toolbar.append('<a href="#" class="button" id="sortButton">Sort Playlist</a>');
        toolbar.append('<a href="#" class="button" id="lockButton">Lock Playlist</a>');
      }
      toolbar.append('<a href="#" class="button" id="skipButton">Skip</a>');
      toolbar.append('<div style="float:right"><span>Name:</span><input id="nameEntry" type="text" value=""/></a>');
      $('#nameEntry')[0].value = Tube.tripcode||'';
    }
    Tube.onUsersChanged = function() {
      $('#userCount').text(Tube.users.length);
      Tube.onChangeSkipCount(Tube.channel);
    }
})();

// Entry
$(document).ready(function() {
  function initVideo()
  {
    var plView = new Tube.Views.PlaylistView({el: $('#playlist')});
    $('#messageEntryBox').keypress(function(evt){
      if (evt.keyCode == 13 && evt.target.value != "") {
        if (evt.target.value.indexOf('/nick') == 0) {
          var newName = evt.target.value.split(' ')[1];
          if (newName)
            Tube.setName(newName);
        } else {
          Tube.sendChat(evt.target.value);
        }
        evt.target.value = '';
      }
    });
    
    $('#userToolbar').on('click', '#leadButton', function(event){
      event.preventDefault();
      Tube.sendMessage({'t': 'leader', 'user_id':Tube.user.get('id')});
    });
    
    $('#userToolbar').on('click', '#skipButton', function(event){
      event.preventDefault();
      Tube.sendMessage({'t': 'skip'});
    });
    
    $('#userToolbar').on('click', '#lockButton', function(event){
      event.preventDefault();
      Tube.sendMessage({'t': 'lock'});
    });
    
    $('#userList').on('click', 'a.buttonKickUser', function(event){
      event.preventDefault();
      var el = $(event.target).parents('li:first');
      Tube.sendMessage({'t': 'kick', 'user_id':el.attr('user_id')});
    });
    
    $('#userList').on('click', 'a.buttonBanUser', function(event){
      event.preventDefault();
      var el = $(event.target).parents('li:first');
      Tube.sendMessage({'t': 'ban', 'user_id':el.attr('user_id')});
    });
    
    $('#userToolbar').on('keypress', '#nameEntry', function(event){
      if (event.keyCode == 13 && event.target.value != "") {
        Tube.setName(event.target.value);
      }
    })
    
    $('#userToolbar').on('click', '#sortButton', function(event){
      event.preventDefault();
      if (Tube.sort) {
        $('#sortButton').text('Sort Playlist');
        $('#playlist').sortable('destroy');
        Tube.sort = false;
      } else {
        Tube.sort = true;
        $('#sortButton').text('Stop Sorting Playlist');
        $('#playlist').sortable({
          update : function () {
            var order = _.map($('#playlist').sortable('toArray'), function(el){ var l=el.split('_'); return parseInt(l[l.length-1]); });
            Tube.sendChat({'t': 'sort_videos', 'order':order});
          }
        }) 
      }
    });
    
    $('#userToolbar').on('click', '#lockButton', function(event){
      event.preventDefault();
      Tube.sendMessage({'t': 'lock', 'locked':!Tube.channel.get('locked')});
    });

    $('#playlistEntryBox').keypress(function(evt){
      if (evt.keyCode == 13 && evt.target.value != "") {
        Tube.sendMessage({'t': 'add_video', 'url': evt.target.value});
        evt.target.value = '';
      }
    });
  };

  function initAdmin()
  {
    Tube.makeAdmin($('#adminroot'));
  };

  if ($('#video')[0])
    initVideo();
  else if ($('#adminroot')[0])
    initAdmin();
});
