(function() {
    Tube = {
        video: null,
        admin: false,
        provider: null,
		handlers: {},
        userList: {}
    };

    // Controller
    Tube.registerHandler = function(provider, handler) {
		Tube.handlers[provider] = handler;
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
            'channel_id': Tube.current_channel,
            'time': newTime
        });
    };
    Tube.onNewVideo = function(url, time) {
      Tube.socket.sendJSON({'t': 'video', 'url': url, 'time': time, 'channel_id': Tube.current_channel, 'provider': this.video.provider});
    };
    Tube.onVideoFinished = function() {
      Tube.socket.sendJSON({'t': 'video_finished', 'channel_id': Tube.current_channel});
    };
    Tube.parseDuration = function(time) {
      var calc = time;
      var minutes = Math.floor(time / 60.0);
      var seconds = time % 60;
      return minutes + ':' + seconds;
    };
    Tube.addPlaylistItem = function(item) {
      //if (!item.playlist)
      //  return;
      var list = $('#playlist');
      var element = $('#playlist_video_' + item.id);
      if (element.length == 0) {
        element = $('#playlist').append('<div class=\'item\' id=\'playlist_video_' + item.id + '\'></div>').children().last();
        element.append('<div class=\'time\'></div>');
        element.append('<div class=\'title\'></div>');
        if (Tube.admin) {
          element.append('<div class=\'delete\'>[X]</div>');
          element.append('<div class=\'clear\'></div>');
        }
      }
      element.attr('position', item.position);
      element.attr('video_id', item.id);
      element.children('.title').text(item.title);
      element.children('.time').text(Tube.parseDuration(item.duration));
      /*
      var items = list.children('.item');
      items.sort(function(a,b){
        var pos_a = parseInt(a.attributes['position'].value);
        var pos_b = parseInt(b.attributes['position'].value);
        return (pos_a < pos_b) ? -1 : (pos_a > pos_b) ? 1 : 0;
      })
      $.each(items, function(idx, sort_item) { list.append(sort_item); })*/
    };
    Tube.removePlaylistItem = function(item) {
      $('#playlist_video_' + item.id).remove();
    };
    Tube.connect = function() {
        $('#status').html('Connecting...');

        Tube.socket = new WebSocket("ws://" + document.location.host + "/ws");
        Tube.socket.sendJSON = function(data) {
            Tube.socket.send(JSON.stringify(data));
        };
        Tube.socket.sendMessage = function(content) {
            Tube.socket.sendJSON({'t': 'message', 'channel_id': Tube.current_channel, 'content': content});
        };
        Tube.pickColor = function(){
          var pick = ['red', 'green', 'blue', 'white', 'yellow'];
          return pick[Math.floor(Math.random()*pick.length)];
        };
        Tube.socket.onmessage = function(evt) {
            var message = JSON.parse(evt.data);
			console.log(message);
            //$("#debug").append("<p>" + evt.data + "</p>");

            if (message.t == 'hello') {
                Tube.socket.onauthenticated(message);
            } else if (message.t == 'goaway') {
                Tube.socket.onauthfailed(message);
			}else if (message.t == 'userjoined') {
                if (Tube.user_id == message.uid) {
                    Tube.admin = (message['scope'] || []).indexOf('admin') >= 0;
                }
                var el;
                if (message.uid.indexOf('anon_') == 0) {
                  el = $('#userlist').append("<li id='user_" + message.uid + "'></li>").children().last();
	              el.text(message.user);
                } else {
                  el = $('#userlist').append("<li id='user_" + message.uid + "'><strong></strong></li>").children().last();
                  el.children('strong').text(message.user);
                }
                Tube.userList[message.uid] = {'name': message.user, 'color': message['color']||Tube.pickColor(), 'scope': message['scope']||[]};
            } else if (message.t == 'userleft') {
                $('#user_' + message.uid).remove();
                delete Tube.userList[message.uid];
            } else if (message.t == 'changename') {
                var oldName = Tube.userList[message.uid].name;
                Tube.userList[message.uid].name = message.user;
                ChatManager.onchangename(message.uid, oldName);
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
        Tube.socket.onclose = function() {
            $('#status').html('Closed');
            $('#userlist').update('');
            Tube.userList = {};
        };
        Tube.socket.onopen = function() {
            Tube.admin = false;
            $('#status').html('Connected');

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
            Tube.user_id = message.uid;
            Tube.user = message.nickname;
            Tube.socket.sendJSON({
                't': 'subscribe',
                'channel_id': Tube.current_channel
            });
        };
        Tube.socket.onauthfailed = function(message) {
           if (message.reason == 'banned') {
				console.log("BANNED");
			} else {
				console.log("OTHER REASON AUTH FAILED:", message);
			}
			
			Tube.socket.close();
		};
    };
    Tube.disconnect = function() {
        Tube.socket.disconnect();
        Tube.socket = null;
    };
})();

// Entry
$(document).ready(function() {
    if (!$('#video'))
    return;

    Tube.connect();
    $('#messageEntryBox').keypress(function(evt){
      if (evt.keyCode == 13) {
        if (evt.target.value.indexOf('/nick') == 0) {
          var newName = evt.target.value.split(' ')[1];
          if (newName)
            Tube.socket.sendJSON({'t': 'changename', 'nickname': newName, 'channel_id': Tube.current_channel});
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
            data: {'uid': Tube.user_id, 'channel_id': Tube.current_channel, 'url': evt.target.value},
            success: function(data) {
                console.log('VIDEO ADDED',data);
            }});
        evt.target.value = '';
      }
    });

    $('#playlist .delete').live('click', function(evt) {
      $.ajax({	
            type: 'DELETE',
            url: '/video',
            data: {'channel_id': Tube.current_channel, 'id': $(evt.target).parent('.item').attr('video_id')},
            success: function(data) {
                console.log('VIDEO DELETED',data);
            }});
    });

    $('#playlist .title').live('click', function(evt) {
      $.ajax({	
            type: 'PUT',
            url: '/video',
            data: {'channel_id': Tube.current_channel, 'id': $(evt.target).parent('.item').attr('video_id')},
            success: function(data) {
                console.log('VIDEO SET',data);
            }});
   });

});
