(function() {
    Tube = {
        video: null,
        admin: false,
        provider: null
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
    };
    YoutubeHandler.prototype.onReady = function() {
        this.control = document.getElementById("video");

        // Play the video
        if (this.nextVideoId != null && this.nextVideoId != this.videoId) {
            this.control.loadVideoById(this.nextVideoId, this.startTime);
            this.videoId = this.nextVideoId;
        } else {
            this.videoUrl = this.control.getVideoUrl();
            console.log('READY:', this.videoUrl);
            this.control.playVideo();
        }

        // Listen for changes if we are controlling
        if (Tube.admin) {
            this.control.addEventListener("onStateChange", 'OnYoutubeStateChange');
            this.control.addEventListener("onError", 'OnYoutubeError');
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
    YoutubeHandler.prototype.setVideo = function(id, startTime) {
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
        if (newState == 1) {
            // Playing
            if (this.control.getVideoUrl() != this.videoUrl) {
                Tube.onNewVideo(this.control.getVideoUrl());
                this.videoUrl = this.control.getVideoUrl();
            }
            var self = this;
            if (!this.timeCheckInterval) {
                Tube.timeCheckInterval = setInterval(function() {
                    Tube.onTimeChange(this.control.getCurrentTime());
                }, 2000);
            }
        } else if (newState == 0) {
            // Stopped
            if (this.timeCheckInterval) {
                clearInterval(this.timeCheckInterval);
            }
            this.timeCheckInterval = null;
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
    BlipHandler.prototype.setVideo = function(id, startTime) {
	    console.log('set blip video to', id, startTime)
        if (this.videoId != id) {
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
            console.log("BLIP LOADED");
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
                        console.log('The wait is over, seek set');
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
            this.video.seek(newTime);
        }
    };
    Tube.setVideo = function(id, startTime, provider) {
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
        this.video.setVideo(id, startTime);
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
    Tube.connect = function() {
        $('#status').html('Connecting...');

        Tube.socket = new WebSocket("ws://" + document.location.host + "/ws");
        Tube.socket.sendJSON = function(data) {
            this.send(JSON.stringify(data));
        };
        Tube.socket.onmessage = function(evt) {
            var message = JSON.parse(evt.data);
            $("#messages").append("<p>" + evt.data + "</p>");

            if (message.type == 'hello') {
                this.onauthenticated(message);
            } else if (message.type == 'userjoined') {
                if (Tube.user == message.user) {
                    Tube.admin = (message['scope'] || []).indexOf('admin') >= 0;
                }
            } else if (message.type == 'video') {
                if (!Tube.admin || Tube.video == null || message.force) {
                    Tube.setVideo(message.url, message.time, message.provider);
                }
            } else if (message.type == 'video_time') {
                // Set the time of the video, ignoring minor offsets
                if (!Tube.admin && Tube.video && Tube.video.control) {
                    var currentTime = Tube.video.currentTime();
                    if ((message.time - currentTime < -Tube.video.timeMargin) || (message.time - currentTime > Tube.video.timeMargin)) {
                        console.log('Adjust offset:', message.time - currentTime);
                        Tube.setTime(message.time);
                    }
                }
            }
        };
        Tube.socket.onclose = function() {
            $('#status').html('Closed');
        };
        Tube.socket.onopen = function() {
            var self = this;
            Tube.admin = false;
            $('#status').html('Connected');

            $.ajax({
                type: 'POST',
                url: '/auth/socket_token',
                success: function(data) {
                    self.sendJSON({
                        'type': 'auth',
                        'auth_token': data.auth_token
                    });
                },
                error: function(xhr, status, error) {
                    console.log('BARF', status, error);
                    self.close();
                }
            });
        };
        Tube.socket.onauthenticated = function(message) {
            Tube.user = message.user;
            this.sendJSON({
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
});
