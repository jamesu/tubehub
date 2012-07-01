(function() {
  // Admin code

  var router;
  var panel = null;


  var AdminUser = Backbone.Model.extend({});
  var AdminBan = Backbone.Model.extend({});
  var AdminChannel = Backbone.Model.extend({});

  var UserList = new Backbone.Collection([], {
    model: AdminUser,
  });
  UserList.url = '/users';
  
  var BanList = new Backbone.Collection([], {
    model: AdminBan,
  });
  BanList.url = '/bans';
  
  var ChannelList = new Backbone.Collection([], {
    model: AdminChannel,
  });
  ChannelList.url = '/channels';
  
  window.UserList = UserList;
  window.BanList = BanList;
  
  var UserFormTemplate = '<form>\
  <% if (model.isNew()) { %>\
  <div>\
    <label for="user_name<%= model.get("id") %>">Username</label>\
    <input id="user_name<%= model.get("id") %>" name="name" type="text" value="<%= model.escape("name") %>"/>\
  </div>\
  <% } %>\
  <div>\
    <label for="user_nick<%= model.get("id") %>">Nickname</label>\
    <input id="user_nick<%= model.get("id") %>" name="nick" type="text" value="<%= model.escape("nick") %>"/>\
  </div>\
  <div>\
    <label for="user_password<%= model.get("id") %>">Password</label>\
    <input id="user_password<%= model.get("id") %>" name="password" type="password"/>\
  </div>\
  <div>\
    <label for="user_password_confirm<%= model.get("id") %>">Confirm Password</label>\
    <input id="user_password_confirm<%= model.get("id") %>" name="password_confirm" type="password"/>\
  </div>\
  <button type="submit">Update</button>\
  Or <a href="#" class="cancel">Cancel</a>\
  <% if (!model.isNew()) { %>\
  Or <a href="#" class="delete">Delete</a>\
  <% } %>\
  </form>';
  
  var BanFormTemplate = '<form>\
  <div>\
    <label for="ban_ip">Ip Address</label>\
    <input id="ban_ip" name="ip" type="text" value="<%= model.escape("ip") %>"/>\
  </div>\
  <div>\
    <label for="ban_duration">Duration (days)</label>\
    <input id="ban_duration" name="duration" type="text" value="<%= model.escape("duration") %>"/>\
  </div>\
  <div>\
    <label for="ban_comment">Comment</label>\
    <input id="ban_comment" name="ban_comment" type="text" value="<%= model.escape("comment") %>"/>\
  </div>\
  <button type="submit">Update</button>\
  Or <a href="#" class="cancel">Cancel</a>\
  <% if (!model.isNew()) { %>\
  Or <a href="#" class="delete">Delete</a>\
  <% } %>\
  </form>';
  
  var NewChannelTemplate = '\<h1>Add Channel</h1><form>\
  <div>\
    <label for="chan_name">Name</label>\
    <input id="chan_name" name="name" type="text" value="<%= channel.escape("name") %>"/>\
  </div>\
  <div>\
    <label for="chan_permalink">Permalink</label>\
    <input id="chan_permalink" name="permalink" type="text" value="<%= channel.escape("permalink") %>"/>\
  </div>\
  <div>\
    <label for="chan_banner">Banner</label>\
    <textarea id="chan_banner" name="banner" type="text" rows="20" cols="60"><%= channel.escape("banner") %></textarea>\
  </div>\
  <div>\
    <label for="chan_footer">Footer</label>\
    <textarea id="chan_footer" name="footer" type="text" rows="20" cols="60"><%= channel.escape("footer") %></textarea>\
  </div>\
  <div>\
    <label for="chan_backend_server">Backend server port (optional for single server)</label>\
    <input id="chan_backend_server" name="backend_server" type="text" value="<%= channel.escape("backend_server") %>"/>\
  </div>\
  <button type="submit">Create</button>\
  Or <a href="#" class="cancel">Cancel</a>\
  </form>\
  ';
  
  var EditChannelTemplate = '\<form>\
  <div>\
    <label for="chan_name">Name</label>\
    <input id="chan_name" name="name" type="text" value="<%= channel.escape("name") %>"/>\
  </div>\
  <div>\
    <label for="chan_permalink">Permalink</label>\
    <input id="chan_permalink" name="permalink" type="text" value="<%= channel.escape("permalink") %>"/>\
  </div>\
  <div>\
    <label for="chan_banner">Banner</label>\
    <textarea id="chan_banner" name="banner" type="text" rows="20" cols="60"><%= channel.escape("banner") %></textarea>\
  </div>\
  <div>\
    <label for="chan_footer">Footer</label>\
    <textarea id="chan_footer" name="footer" type="text" rows="20" cols="60"><%= channel.escape("footer") %></textarea>\
  </div>\
  <div>\
    <label for="chan_backend_server">Backend server port (optional for single server)</label>\
    <input id="chan_backend_server" name="backend_server" type="text" value="<%= channel.escape("backend_server") %>"/>\
  </div>\
  <div>\
    <label for="chan_moderators">Moderators</label>\
    <textarea id="chan_moderators" name="moderator_list" type="text" rows="20" cols="60"><%= channel.escape("moderator_list") %></textarea>\
  </div>\
  <div>\
    <label for="chan_skip_limit">Skip Limit</label>\
    <input id="chan_skip_limit" name="skip_limit" type="text" value="<%= channel.escape("skip_limit") %>"/>\
  </div>\
  <div>\
    <label for="chan_video_limit">Video Limit</label>\
    <input id="chan_video_limit" name="video_limit" type="text" value="<%= channel.escape("video_limit") %>"/>\
  </div>\
  <button type="submit">Update</button>\
  Or <a href="#" class="cancel">Cancel</a>\
  Or <a href="#" class="delete">Delete</a>\
  </form>\
  ';
  
  var AdminGeneralTemplate = '\
    <p><strong>Total Connections:</strong> <%= stats.subscriptions.connections %></p>\
    <% _.each(_.keys(stats.subscriptions.channels), function(key){ %> \
      <p><strong><%= key %>:</strong><%= stats.subscriptions.channels[key] %></p>\
    <% }); %>\
  ';
  
  var BaseForm = {
    tagName: 'div',
    events: {
      "submit form": "submitForm",
      'click a.cancel': 'cancelForm',
      'click a.delete': 'deleteObject',
    }
  };
  
  BaseForm.render = function() {
    var el = $(this.el).empty();
    
    el.append(this.template({model: this.model}));
    
    return this;
  }
  
  BaseForm.updateFields = function(model) {
    
  }
  
  BaseForm.onObjectRemoved = function(model) {
    
  }
  
  BaseForm.deleteObject = function(event) {
    event.preventDefault();
    
    if (!confirm('Are you sure you want to delete this?'))
      return;
      
    var el = $(this.el);
    var form = this;
    el.addClass('loading');
    
    this.model.destroy({
      success: function() { form.cancelForm(event); form.onObjectRemoved(this.model); },
      error: function() { el.removeClass('loading'); alert('Error deleting object'); }
    });
  }
  
  BaseForm.revealErrors = function(prefix, model, errors) {
    var form = $(this.el).find('form:first');
    
    form.find('.error_field').remove();
    form.find('.error').removeClass('error');
    _.each(_.keys(errors), function(key){
      
      // Make sure errors for this field is a list
      var field_errors;
      if (typeof errors[key] == "string") {
        field_errors = [errors[key]];
      } else {
        field_errors = errors[key];
      }
      
      var el = form.find('*[name="' + key + '"]').addClass('error');
      
      _.each(field_errors, function(error) {
        el.after('<div class="error_field">' + error + '</div>');
      });
    });
  }
  
  BaseForm.cancelForm = function(event) {
    event.preventDefault();
    this.unbind();
    this.remove();
  }
  
  Tube.Views.BaseForm = Backbone.View.extend(BaseForm);
  
  
  var NewUserForm = {
    className: 'user_form',
    template: _.template(UserFormTemplate)
  };
  
    
  NewUserForm.submitForm = function(evt) {
    // Change state of form
    evt.preventDefault();
    
    var el = $(this.el);
    el.addClass('loading');
    
    var form = this;
    var model = this.model;
    this.model.urlRoot = '/users';
    this.model.save($(this.el).children('form').serializeObject(), {
      success: function(){ el.removeClass('loading'); panel.addUser(model); },
      error: function(originalModel, resp, option){ el.removeClass('loading'); form.revealErrors('user', originalModel, JSON.parse(resp.responseText).errors); }
    });
  }

  NewUserForm.render = function() {
    var el = $(this.el).empty();
    
    el.append(this.template({model:this.model}));
    
    this.updateFields();
    
    return this;
  }
  
  Tube.Views.NewUserForm = Tube.Views.BaseForm.extend(NewUserForm);
  
  
  var EditUserForm = {
    className: 'user_form',
    template: _.template(UserFormTemplate)
  };
  
  EditUserForm.submitForm = function(evt) {
    // Change state of form
    evt.preventDefault();
    
    var el = $(this.el);
    el.addClass('loading');
    
    var model = this.model;
    var form = this;
    this.model.save($(this.el).children('form').serializeObject(), {
      success: function(){ el.removeClass('loading'); form.remove(); },
      error: function(originalModel, resp, option){ el.removeClass('loading'); form.revealErrors('user', originalModel, JSON.parse(resp.responseText).errors); }
    });
  }
    
  EditUserForm.updateFields = function() {
    var form = el.find('form:first');
    return this;
  }
  
  Tube.Views.EditUserForm = Tube.Views.BaseForm.extend(EditUserForm);

  var UserListPanel = {
    tagName: 'div',
    id: 'useredit',
    events: {
      "click a.add_user": 'createUser',
      "click a.edit": 'editUser'
    }
  }
  
  UserListPanel.initialize = function() {
    UserList.bind('add', this.addUser, this);
    UserList.bind('reset', this.addUsers, this);
  
    UserList.fetch();
  }

  UserListPanel.renderUserRow = function(user, el) {
    el.empty();
    el.append('<span class="user"></span>').children().last().text(user.get('name'));
    el.append('<a href="#" class=\"edit\">Edit</a>');

    var detail = el.append('<div class="detail"></div>').children().last();

    return el;
  },

  UserListPanel.updateUserRow = function(user) {
    this.renderUserRow(user, $('user_row_' + user.get('id')));
  }

  // Create user view
  UserListPanel.addUser = function(user) {
    var row = $(this.el).append('<div class="user_row" id="user_row_'+user.get('id')+'" user_id="'+user.get('id')+'"></div>').children().last();
    this.renderUserRow(user, row);
  
    user.bind("change", this.updateUserRow, this);
  }

  UserListPanel.addUsers = function(users) {
    this.render();
    users.each(this.addUser, this);
  },

  UserListPanel.editUser = function(event) {
    event.preventDefault();
  
    var user_el = $(event.target).parents('.user_row:first');
    if (user_el.find('form')[0])
      return;
    
    var edit = new Tube.Views.EditUserForm({model: UserList.get(user_el.attr('user_id'))});
    user_el.append(edit.render().el);

    return false;
  }

  // Opens the user form
  UserListPanel.createUser = function(event) {
    event.preventDefault();
    
    if ($('#useredit').find('.user_form')[0])
      return;
    var form = new Tube.Views.NewUserForm({model: new AdminUser({})});
    $('#useredit').prepend(form.render().el);
  }

  UserListPanel.render = function() {
    var el = $(this.el).empty();
    el.append('<a href="#" class="add_user">' + 'Add User' + '</a>');
    return this;
  }
  
  
  Tube.Views.UserListPanel = Backbone.View.extend(UserListPanel);
  
  
  var EditBanForm = {
    className: 'ban_form',
    template: _.template(BanFormTemplate)
  };
  EditBanForm.initialize = function(options) {
    this.edit_type = options.edit_type;
  }
  EditBanForm.submitForm = function(evt) {
    // Change state of form
    evt.preventDefault();
    
    var el = $(this.el);
    el.addClass('loading');
    
    var form = this;
    var model = this.model;
    this.model.urlRoot = '/bans';
    this.model.save($(this.el).children('form').serializeObject(), {
      success: function(){ el.removeClass('loading'); panel.addBan(model); form.remove(); },
      error: function(originalModel, resp, option){ el.removeClass('loading'); form.revealErrors('ban', originalModel, JSON.parse(resp.responseText).errors); }
    });
  }
  
  Tube.Views.EditBanForm = Tube.Views.BaseForm.extend(EditBanForm);

  var BanListPanel = {
    tagName: 'div',
    id: 'banedit',

    events: {
      "click a.add_ban": 'createBan',
      "click a.edit": 'editBan'
    }
  }
    
  BanListPanel.initialize = function() {
    BanList.bind('add', this.addBan, this);
    BanList.bind('remove', this.removeBan, this);
    BanList.bind('reset', this.addBans, this);
    
    BanList.fetch();
  }

  BanListPanel.renderBanRow = function(ban, el) {
    el.empty();
    el.append('<span class="ip"></span>').children().last().text(ban.get('ip'));
    el.append('<span class="start_date"></span>').children().last().text(ban.get('created_at'));
    el.append('<span class="end_date"></span>').children().last().text(ban.get('ended_at'));
    el.append('<span class="comment"></span>').children().last().text(ban.get('comment'));
    el.append('<a href="#" class=\"edit\">Edit</a>');

    var detail = el.append('<div class="detail"></div>').children().last();

    return el;
  },

  BanListPanel.updateBanRow = function(ban) {
    this.renderBanRow(user, $('ban_row_' + ban.get('id')));
  }
  
  // Create user view
  BanListPanel.addBan = function(ban) {
    var row = $(this.el).append('<div class="ban_row" id="ban_row_'+ban.get('id')+'" ban_id="'+ban.get('id')+'"></div>').children().last();
    this.renderBanRow(ban, row);
  
    ban.bind("change", this.updateBanRow, this);
  }
  
  BanListPanel.removeBan = function(ban) {
    $('#ban_row_' + ban.get('id')).remove();
  }
  
  BanListPanel.addBans = function(bans) {
    this.render();
    bans.each(this.addBan, this);
  }
  
  // Opens the user form
  BanListPanel.createBan = function(event) {
    event.preventDefault();
  
    if ($('#banedit').find('.ban_form')[0])
      return;
    var form = new Tube.Views.EditBanForm({edit_type: 'new', model: new AdminBan({})});
    $('#banedit').prepend(form.render().el);
  }
  
  BanListPanel.editBan = function(event) {
    event.preventDefault();
  
    var ban_el = $(event.target).parents('.ban_row:first');
    var edit = new Tube.Views.EditBanForm({edit_type: 'edit', model: BanList.get(ban_el.attr('ban_id'))});
    ban_el.after(edit.render().el);

    return false;
  }

  BanListPanel.render = function() {
    var el = $(this.el).empty();
    el.append('<a href="#" class="add_ban">' + 'Add Ban' + '</a>');
    return this;
  }
  
  Tube.Views.BanListPanel = Backbone.View.extend(BanListPanel);
  
  var ChannelListPanel = {
    tagName: 'div',
    id: 'chanedit',
    
    rowTemplate: _.template('<div class="chan_row" id="chan_row_<%= channel.get("id") %>" chan_id="<%= channel.get("id") %>"><a href="#" class="edit"><span class="permalink"><%= channel.escape("permalink") %></span><span class="name"><%= channel.escape("name") %></span></a></div>'),

    events: {
      "click a.add_channel": 'createChannel',
      "click a.edit": 'editChannel'
    }
  }
    
  ChannelListPanel.initialize = function() {
    ChannelList.bind('add', this.addChannel, this);
    ChannelList.bind('reset', this.addChannels, this);
    
    ChannelList.fetch();
  }
  
  ChannelListPanel.updateChannelRow = function(channel) {
    this.renderChannelRow(channel, $('chan_row_' + channel.get('id')));
  }
  
  ChannelListPanel.renderChannelRow = function(channel, el) {
    el.replaceWith(this.rowTemplate({channel:channel}));
    return this;
  }
  
  // Create user view
  ChannelListPanel.addChannel = function(channel) {
    var row = $(this.el).append('<div></div>').children().last();
    this.renderChannelRow(channel, row);

    channel.bind("change", this.updateChannelRow, this);
  }
  
  ChannelListPanel.addChannels = function(channels) {
    this.render();
    channels.each(this.addChannel, this);
  }
  
  ChannelListPanel.editChannel = function(event) {
    event.preventDefault();
  
    var chan_el = $(event.target).parents('.chan_row:first');
    // Navigate to edit channel view
    Backbone.history.navigate('admin/channels/' + chan_el.attr('chan_id'), {trigger:true});
  }
  
  // Opens the user form
  ChannelListPanel.createChannel = function(event) {
    event.preventDefault();
    Backbone.history.navigate('admin/channels/new', {trigger:true});
  }

  ChannelListPanel.render = function() {
    var el = $(this.el).empty();
    el.append('<a href="#" class="add_channel">' + 'Add Channel' + '</a>');
    return this;
  }
  
  Tube.Views.ChannelListPanel = Backbone.View.extend(ChannelListPanel);
  
  var ChannelEditPanel = {
    tagName: 'div',
    id: 'chanedit',
    
    newTemplate: _.template(NewChannelTemplate),
    editTemplate: _.template(EditChannelTemplate),
  }
    
  ChannelEditPanel.initialize = function(options) {
    this.edit_type = options.edit_type;
  }
  
  ChannelEditPanel.submitForm = function(evt) {
    // Change state of form
    evt.preventDefault();
    
    var el = $(this.el);
    el.addClass('loading');
    
    var form = this;
    
    if (this.edit_type == 'new') {
      var model = this.model;
      this.model.urlRoot = '/channels';
      this.model.save($(this.el).children('form').serializeObject(), {
        success: function(){ el.removeClass('loading'); ChannelList.add(this); Backbone.history.navigate('admin/channels/' + form.model.get('id'), {trigger:true}); },
        error: function(originalModel, resp, option){ el.removeClass('loading'); form.revealErrors('chan', originalModel, JSON.parse(resp.responseText).errors); }
      });
    } else {
      var model = this.model;
      this.model.save($(this.el).children('form').serializeObject(), {
        success: function(){ el.removeClass('loading'); Backbone.history.navigate('admin/channels', {trigger:true}); },
        error: function(originalModel, resp, option){ el.removeClass('loading'); form.revealErrors('chan', originalModel, JSON.parse(resp.responseText).errors); }
      });
    }
  }
  
  ChannelEditPanel.cancelForm = function(event) {
    event.preventDefault();
    Backbone.history.navigate('admin/channels', {navigate:true});
  } 

  ChannelEditPanel.render = function() {
    var el = $(this.el).empty();
    
    if (this.edit_type == 'new') {
      el.append(this.newTemplate({channel:this.model}));
    } else {
      el.append(this.editTemplate({channel:this.model}));
    }
    
    return this;
  }
  
  Tube.Views.ChannelEditPanel = Tube.Views.BaseForm.extend(ChannelEditPanel);
  
  
  var AdminStatPanel = {
    tagName: 'div',
    id: 'statpanel',
    
    generalTemplate: _.template(AdminGeneralTemplate),

    events: {
    }
  }
    
  AdminStatPanel.initialize = function() {
  }
  
  AdminStatPanel.pollStats = function() {
    var admin_panel = this;
    $.get('/stats', function(data) {
      if (panel == admin_panel) {
        admin_panel.lastStats = data;
        admin_panel.updateStats();
        setTimeout(function() { admin_panel.pollStats(); }, 3000);
      }
    });
  }
  
  AdminStatPanel.updateStats = function() {
    var general = $('#adminsection_general').empty();
    
    general.append(this.generalTemplate({stats: this.lastStats}));
  }

  AdminStatPanel.render = function() {
    var el = $(this.el).empty();
    el.append('<div class="adminsection">General Stats</div>');
    el.append('<div id="adminsection_general"></div>');
    return this;
  }
  
  AdminStatPanel.remove = function() {
    if (this.pollTimeout)
      cancelTimeout(this.pollTimeout);
    $(this.el).remove();
    return this;
  }
  
  Tube.Views.AdminStatPanel = Backbone.View.extend(AdminStatPanel);

  // Navigation
  var AdminPanelController = Backbone.Router.extend({

    routes: {
      "admin":                          "index",
      "admin/users":                    "users",
      "admin/bans":                     "bans",
      "admin/channels":                 "channels",
      "admin/channels/new":             "channel_new",
      "admin/channels/:id":             "channel_edit"
    },

    setTab: function(tabName) {
      $('#tabsWrapper ul li a').removeClass('active');
      $('#tabsWrapper ul #tab_' + tabName + ' a').addClass('active');
      //$('#panel_title').text($('#tab_' + tabName + ' a').text());
      this.currentTab = tabName;
    },
    
    errorPanel: function(status) {
      if (status == 404) {
        $('#adminroot').text('404 Not Found');
      } else {
        $('#adminroot').text(status + ' Error');
      }
    },

    clearPanel: function() {
      if (panel) {
        panel.unbind();
        panel.remove();
      }
    },

    index: function() {
      this.clearPanel();
      this.setTab('admin');
      
      panel = new Tube.Views.AdminStatPanel();
      panel.pollStats();
      $('#adminroot').empty().append(panel.render().el);
    },

    bans: function() {
      //
      this.clearPanel();
      this.setTab('admin_bans');

      panel = new Tube.Views.BanListPanel();
      $('#adminroot').empty().append(panel.render().el);
    },
    
    channel_new: function() {
      //
      this.clearPanel();
      this.setTab('admin_channels');

      panel = new Tube.Views.ChannelEditPanel({edit_type: 'new', model: new AdminChannel()});
      $('#adminroot').empty().append(panel.render().el);
    },

    channel_edit: function(channel_id) {
      //
      this.clearPanel();
      this.setTab('chan_' + channel_id);
      ChannelList.fetch({
        success: function(){
          panel = new Tube.Views.ChannelEditPanel({edit_type: 'edit', model: ChannelList.get(channel_id)});
          $('#adminroot').empty().append(panel.render().el);
        },
        error: function(){
          router.errorPanel(404);
        }
        });
    },

    channels: function() {
      //
      this.clearPanel();
      this.setTab('admin_channels');

      panel = new Tube.Views.ChannelListPanel();
      $('#adminroot').empty().append(panel.render().el);
    },

    users: function() {
      //
      this.clearPanel();
      this.setTab('admin_users');

      panel = new Tube.Views.UserListPanel();
      $('#adminroot').empty().append(panel.render().el);
    }

  });

  Tube.makeAdmin = function(root) {
    router = new AdminPanelController();
    
    UserList.fetch({success: function(){
      Backbone.history.start({pushState: true});
    }});
    
    // Update tabs when channels change
    var addModelTab = function(model) {
      var tab = $('#tabsWrapper ul').append('<li id="tab_chan_' + model.get('id') + '" class="room"><a href="/admin/channels/' + model.get('id') + '">' + model.escape('permalink') + '</a></div>').children().last();
      if (router.currentTab == 'chan_' + model.get('id')) {
        tab.children('a').addClass('active');
      }
    }
    ChannelList.bind('add',addModelTab);
    ChannelList.bind('change:name', function(model){
      $('#tab_chan_' + model.get('id')).text(model.get('name'));
    });
    ChannelList.bind('reset', function(models){
      $('#tabsWrapper ul li.room').remove();
      models.each(addModelTab);
    });
    ChannelList.bind('remove', function(model){
      $('#tab_chan_' + model.get('id')).remove();
    });
    
    $('#tabsWrapper').on("click", "ul li a", function(event){
      event.preventDefault();
      router.navigate($(this).attr('href').substring(1), {trigger: true});
    });
  };


})();