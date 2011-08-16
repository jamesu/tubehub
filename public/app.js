(function() {
    Tube = {
        video: null,
        admin: false,
        provider: null,
        userList: {}
    };

    // Youtube code
    var YoutubeHandler = function() {
        this.provider = 'youtube';
        this.loadedControl = false;
        this.videoId = null;
        this.nextVideoId = null;
        this.videoUrl = null;
        // tracks changes in playback url
        this.startTime = 0;
        this.timeCheckInterval = null;
        this.timeMargin = 1.0;
        this.force = false;
    };
    YoutubeHandler.prototype.onReady = function() {
        this.control = document.getElementById("video");

        // Play the video
        if (this.nextVideoId != null && this.nextVideoId != this.videoId) {
            this.control.loadVideoById(this.nextVideoId, this.startTime);
            this.videoId = this.nextVideoId;
        } else {
            this.videoUrl = this.control.getVideoUrl();
            if (this.startTime > 0)
              this.control.seekTo(this.startTime, true)
            else
              this.control.playVideo();
        }

        // Listen for changes if we are controlling
        if (Tube.admin) {
            this.control.addEventListener("onStateChange", 'HandleYouTubeStateChange');
            this.control.addEventListener("onError", 'HandleYouTubeError');
        }
    };
    YoutubeHandler.prototype.play = function() {
        if (this.control) {
            this.control.playVideo();
        }
    };
    YoutubeHandler.prototype.stop = function() {
        if (this.timeCheckInterval) {
            clearInterval(this.timeCheckInterval);
        }
        this.timeCheckInterval = null;
        if (this.control) {
            this.control.stopVideo();
        }
    };
    YoutubeHandler.prototype.seek = function(time) {
        if (this.control) {
            this.control.seekTo(time, true);
        } else {
            this.startTime = time;
        }
    };
    YoutubeHandler.prototype.currentTime = function() {
        if (this.control) {
            return this.control.getCurrentTime();
        } else {
            return 0;
        }
    };
    YoutubeHandler.prototype.setVideo = function(id, startTime, force) {
        this.force = force;
        this.startTime = startTime;
        if (!this.loadedControl) {
            // Make the damn control
            var params = {
                allowScriptAccess: "always"
            };
            var attrs = {
                id: "video"
            };
            var url = "http://www.youtube.com/e/" + id + "?enablejsapi=1&playerapiid=ytplayer";
            swfobject.embedSWF(url, "video", "425", "356", "8", null, null, params, attrs);
            this.loadedControl = true;
            this.videoId = id;
            this.videoUrl = null;
        } else if (this.control) {
            // Set the damn video
            this.videoId = id;
            this.control.loadVideoById(id, startTime);
        } else {
            // Control still loading
            this.nextVideoId = id;
            this.startTime = startTime;
        }
    };
    YoutubeHandler.prototype.onStateChange = function(newState) {
	    //console.log('STATE CHANGE', newState);
        if (newState == 1) {
            // Playing
            //console.log('PLAYING: ', this.control.getVideoUrl(), this.videoUrl);
            if (!this.force && (this.control.getVideoUrl() != this.videoUrl)) {
                Tube.onNewVideo(this.control.getVideoUrl());
            }
            this.force = false;
            this.videoUrl = this.control.getVideoUrl();
            var self = this;
            if (!this.timeCheckInterval) {
                Tube.timeCheckInterval = setInterval(function() {
                    Tube.onTimeChange(self.control.getCurrentTime());
                }, 2000);
            }
        } else if (newState == 0) {
            // Stopped
            if (this.timeCheckInterval) {
                clearInterval(this.timeCheckInterval);
            }
            this.timeCheckInterval = null;
            Tube.onVideoFinished();
        }
    };
    YoutubeHandler.prototype.onError = function(code) {
        console.log('Youtube error:', code);
    };

    // Bliptv code
    var BlipHandler = function() {
        this.provider = 'blip';
        this.loadedControl = false;
        this.videoId = null;
        this.videoUrl = null;
        this.startTime = 0;
        this.lastTime = 0;
        this.videoTimeChecked = null;
        this.videoTime = 0;
        this.waitLoading = false;
        this.waitAd = false;
        this.timeMargin = 2.0;
    };
    BlipHandler.prototype.play = function() {
        if (this.control) {
            this.control.sendEvent('play');
            this.control.sendEvent('seek', this.startTime);
        }
    };
    BlipHandler.prototype.stop = function() {
        if (this.timeCheckInterval) {
            clearInterval(this.timeCheckInterval);
        }
        this.timeCheckInterval = null;
        this.control.sendEvent('pause');
    };
    BlipHandler.prototype.seek = function(time) {
        if (this.control) {
            this.control.sendEvent('seek', time);
            this.videoTime = time;
        } else {
            this.startTime = time;
        }
    };
    BlipHandler.prototype.currentTime = function() {
        if (this.control && this.videoTimeChecked) {
            var delta_s = ((new Date()) - this.videoTimeChecked) / 1000.0;
            return this.videoTime + delta_s;
        } else {
            return 0;
        }
    };
    BlipHandler.prototype.setVideo = function(id, startTime, force) {
	    this.force = force;
        if (this.videoId != id || this.force) {
            // Doesn't seem to be any way of setting the url, so recreate the control
            this.videoUrl = "http://blip.tv/play/" + id;
            this.waitLoading = true;
            this.waitAd = true;
            this.videoId = id;
            this.control = null;
            this.loadedControl = false;
            this.videoTimeChecked = null;
            this.startTime = startTime;
            var params = {
                allowScriptAccess: "always",
                movie: this.videoUrl
            };
            var attrs = {
                id: "video"
            };
            swfobject.embedSWF(this.videoUrl, "video", "425", "356", "8", null, null, params, attrs);
        }
        this.force = false;
    };
    BlipHandler.prototype.onTimeChange = function(newTime) {
        // Dispatch video time if we're an admin
        if (Tube.admin && ((newTime - this.lastTime >= 2) || (newTime - this.lastTime <= -2))) {
            Tube.onTimeChange(newTime);
            this.lastTime = newTime;
        }
        this.videoTimeChecked = new Date();
        this.videoTime = newTime;
    };
    BlipHandler.prototype.onStateChange = function(newState, param, value) {
        //console.log('update', newState, param, value)
        if (!this.control) {
            this.control = document.getElementById("video");
            this.loadedControl = true;
            //console.log("BLIP LOADED");
            this.play();
            this.control.addJScallback("current_time_change", 'HandleBlipTimeChange');
        }
        if (this.control) {
            if (newState == 'player_state_change') {
                if (param == 'loading' && this.waitLoading) {
                    this.waitLoading = false;
                    this.lastTime = -100;
                    Tube.onNewVideo(this.videoUrl);
                } else if (param == 'playing') {
                    if (param == 'playing' && this.startTime > 0 && this.waitAd) {
                        //console.log('The wait is over, seek set');
                        this.seek(this.startTime);
                        this.waitAd = false;
                    }
                } else if (value2 == 'playlist_complete') {
                    // We're done? wow!
                }
            }
        }
    };

    // Controller
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
            if (provider == 'youtube') {
                this.video = new YoutubeHandler();
            } else if (provider == 'blip') {
                this.video = new BlipHandler();
            } else {
                return;
            }
        }
        this.video.setVideo(id, startTime, force);
        this.offsetTime = (new Date()) - startTime;
    };
    Tube.onTimeChange = function(newTime) {
        Tube.socket.sendJSON({
            'type': 'video_time',
            'channel_id': Tube.current_channel,
            'time': newTime
        });
    };
    Tube.onNewVideo = function(url, time) {
      Tube.socket.sendJSON({'type': 'video', 'url': url, 'time': time, 'channel_id': Tube.current_channel, 'provider': this.video.provider});
    };
    Tube.onVideoFinished = function() {
      Tube.socket.sendJSON({'type': 'video_finished', 'channel_id': Tube.current_channel});
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
            Tube.socket.sendJSON({'type': 'message', 'channel_id': Tube.current_channel, 'content': content});
        };
        Tube.socket.onmessage = function(evt) {
            var message = JSON.parse(evt.data);
            //$("#debug").append("<p>" + evt.data + "</p>");

            if (message.type == 'hello') {
                Tube.socket.onauthenticated(message);
            } else if (message.type == 'userjoined') {
                if (Tube.user_id == message.user_id) {
                    Tube.admin = (message['scope'] || []).indexOf('admin') >= 0;
                }
                var el;
                if (message.user_id.indexOf('anon_') == 0) {
                  el = $('#userlist').append("<li id='user_" + message.user_id + "'></li>").children().last();
	              el.text(message.user);
                } else {
                  el = $('#userlist').append("<li id='user_" + message.user_id + "'><strong></strong></li>").children().last();
                  el.children('strong').text(message.user);
                }
                Tube.userList[message.user_id] = {'name': message.user, 'scope': message['scope']||[]};
            } else if (message.type == 'userleft') {
                $('#user_' + message.user_id).remove();
                delete Tube.userList[message.user_id];
            } else if (message.type == 'changename') {
                var oldName = Tube.userList[message.user_id].name;
                Tube.userList[message.user_id].name = message.user;
                $('#user_' + message.user_id).text(message.user);
                var el = $('#messages').append('<div><strong class="u1"></strong> is now known as <strong class="u2"></strong>').children().last();
                el.children('.u1').text(oldName);
                el.children('.u2').text(message.user);
            } else if (message.type == 'message') {
                var el = $('#messages').append("<div><strong></strong><div></div></div>").children().last();
                el.children('div').text(message.content);
                el.children('strong').text(Tube.userList[message.user_id].name + ':');
                var messages = document.getElementById('messages');
                messages.scrollTop = messages.scrollHeight;
            } else if (message.type == 'playlist_video') {
                Tube.addPlaylistItem(message);
            } else if (message.type == 'playlist_video_removed') {
                Tube.removePlaylistItem(message);
            } else if (message.type == 'video') {
                if (!Tube.admin || Tube.video == null || message.force) {
                    Tube.setVideo(message.url, message.time, message.provider, message.force);
                }
            } else if (message.type == 'video_time') {
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
                        'type': 'auth',
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
            Tube.user_id = message.user_id;
            Tube.user = message.nickname;
            Tube.socket.sendJSON({
                'type': 'subscribe',
                'channel_id': Tube.current_channel
            });
        };
    };
    Tube.disconnect = function() {
        Tube.socket.disconnect();
        Tube.socket = null;
    };
})();

// Youtube callbacks
function HandleYouTubeStateChange(value) {
    Tube.video.onStateChange(value);
}

function HandleYouTubeError(code) {
    Tube.video.onError(code);
}

function onYouTubePlayerReady(playerId) {
    Tube.video.onReady();
}

// Blip callbacks
function HandleBlipTimeChange(value) {
    Tube.video.onTimeChange(value);
}

function getUpdate(value, value2, value3) {
    Tube.video.onStateChange(value, value2, value3);
}

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
            Tube.socket.sendJSON({'type': 'changename', 'nickname': newName, 'channel_id': Tube.current_channel});
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
            data: {'user_id': Tube.user_id, 'channel_id': Tube.current_channel, 'url': evt.target.value},
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
