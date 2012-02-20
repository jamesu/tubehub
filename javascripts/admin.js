(function() {
  // Admin code

  var router;
  var panel = null;


  var AdminUser = Backbone.Model.extend({});
  var AdminBan = Backbone.Model.extend({});

  var UserList = new Backbone.Collection([], {
    model: AdminUser,
  });
  UserList.url = '/users';
  
  var BanList = new Backbone.Collection([], {
    model: AdminBan,
  });
  BanList.url = '/bans';
  
  window.UserList = UserList;
  window.BanList = BanList;
  
  var UserFormTemplate = '\
  <div>\
    <label for="user_name>">Username</label>\
    <input id="user_name" name="name" type="text"/>\
  </div>\
  <div>\
    <label for="user_password>">Password</label>\
    <input id="user_password" name="password" type="text"/>\
  </div>\
  <div>\
    <label for="user_password_confirm>">Confirm Password</label>\
    <input id="user_password_confirm" name="password_confirm" type="text"/>\
  </div>\
  <button type="submit">Add user</button>\
  Or <a href="#" class="cancel">Cancel</a>\
  ';
  
  var EditUserFormTemplate = '\
  <div>\
    <label for="user_name>">Username</label>\
    <input id="user_name" name="name" type="text"/>\
  </div>\
  <div>\
    <label for="user_password>">Password</label>\
    <input id="user_password" name="password" type="password"/>\
  </div>\
  <div>\
    <label for="user_password_confirm>">Confirm Password</label>\
    <input id="user_password_confirm" name="password_confirm" type="password"/>\
  </div>\
  <button type="submit">Update user</button>\
  Or <a href="#" class="cancel">Cancel</a>\
  ';
  
  var BanFormTemplate = '\
  <div>\
    <label for="ban_ip>">Ip Address</label>\
    <input id="ban_ip" name="ip" type="text"/>\
  </div>\
  <div>\
    <label for="ban_duration>">Duration (days)</label>\
    <input id="ban_duration" name="duration" type="text"/>\
  </div>\
  <div>\
    <label for="ban_comment>">Comment</label>\
    <input id="ban_comment" name="ban_comment" type="text"/>\
  </div>\
  <button type="submit">Update user</button>\
  Or <a href="#" class="cancel">Cancel</a>\
  ';
  
  var BaseForm = Backbone.View.extend({
    tagName: 'div',
    events: {
      "submit form": "submitForm",
      'click a.cancel': 'cancelForm'
    },
    
    cancelForm: function(evt) {
      this.unbind();
      this.remove();
    }
  });
  
  
  var NewUserForm = BaseForm.extend({
    className: 'user_form',
    template: _.template(UserFormTemplate),
    
    submitForm: function(evt) {
      // Change state of form
      evt.preventDefault();
      
      var el = $(this.el);
      el.addClass('loading');
      
      var model = this.model;
      this.model.urlRoot = '/users';
      this.model.save($(this.el).children('form').serializeObject(), {
        success: function(){ el.removeClass('loading'); panel.addUser(model); },
        error: function(){ console.log('ERROR');}
      });
    },

    render: function() {
      var el = $(this.el).empty();
      
      var form = el.append('<form></form>').children().last();
      //form.append('<input name="_method" value="post"/>');
      form.append(this.template());
      
      return this;
    }

  });
  
  
  var EditUserForm = BaseForm.extend({
    className: 'user_form',
    template: _.template(EditUserFormTemplate),
    
    submitForm: function(evt) {
      // Change state of form
      evt.preventDefault();
      
      var el = $(this.el);
      el.addClass('loading');
      
      var model = this.model;
      var view = this;
      this.model.save($(this.el).children('form').serializeObject(), {
        success: function(){ console.log('succ');el.removeClass('loading'); },
        error: function(){ console.log('ERROR');}
      });
    },
    
    render: function() {
      var el = $(this.el).empty();
      
      var form = el.append('<form></form>').children().last();
      //form.append('<input name="_method" value="post"/>');
      form.append(this.template());
      
      form.find('#user_name').attr('value', this.model.get('name'));
      
      return this;
    }

  });

  var BanListRow = Backbone.View.extend({
    tagName: 'div',
    className: 'ban_row',

    events: {
      "click a.edit": "edit"
    },
    
    initialize: function() {
      this.model.bind("change", this.render, this);
    },

    edit: function() {
      var edit = new EditBanForm({model: this.model});
      $(this.el).append(edit.render().el);

      return false;
    },

    render: function() {
      var el = $(this.el).empty();

      el.append('<span class="ip"></span>').children().last().text(this.model.get('ip'));
      el.append('<span class="start_date"></span>').children().last().text(this.model.get('created_at'));
      el.append('<span class="end_date"></span>').children().last().text(this.model.get('ended_at'));
      el.append('<span class="comment"></span>').children().last().text(this.model.get('comment'));
      el.append('<a href="#" class=\"edit\">Edit</a>');

      var detail = el.append('<div class="detail"></div>').children().last();


      return this;
    }

  });

  var UserListRow = Backbone.View.extend({
    tagName: 'div',
    className: 'user_row',

    events: {
      "click a.edit": "edit"
    },
    
    initialize: function() {
      this.model.bind("change", this.render, this);
    },

    edit: function() {
      var edit = new EditUserForm({model: this.model});
      $(this.el).append(edit.render().el);

      return false;
    },

    render: function() {
      var el = $(this.el).empty();

      el.append('<span class="user"></span>').children().last().text(this.model.get('name'));
      el.append('<a href="#" class=\"edit\">Edit</a>');

      var detail = el.append('<div class="detail"></div>').children().last();


      return this;
    }

  });

  var UserListPanel = Backbone.View.extend({
    tagName: 'div',
    id: 'useredit',

    events: {
      "click a.add_user": 'createUser'
    },
    
    initialize: function() {
      UserList.bind('add', this.addUser, this);
      UserList.bind('reset', this.addUsers, this);
      //UserList.bind('all', this.render, this);
      
      UserList.fetch();
    },
    
    // Create user view
    addUser: function(user) {
      var view = new UserListRow({model: user});
      $('#useredit').append(view.render().el);
    },
    
    addUsers: function(users) {
      this.render();
      console.log('addUsers:...',users);
      users.each(this.addUser);
    },
    
    // Opens the user form
    createUser: function() {
      if ($('#useredit').find('.user_form')[0])
        return;
      var form = new NewUserForm({model: new AdminUser({})});
      $('#useredit').prepend(form.render().el);
    },

    render: function() {
      var el = $(this.el).empty();
      el.append('<a href="#" class="add_user">' + 'Add User' + '</a>');
      return this;
    }

  });
  
  
  
  var NewBanForm = BaseForm.extend({
    className: 'ban_form',
    template: _.template(BanFormTemplate),
    
    submitForm: function(evt) {
      // Change state of form
      evt.preventDefault();
      
      var el = $(this.el);
      el.addClass('loading');
      
      var model = this.model;
      this.model.urlRoot = '/bans';
      this.model.save($(this.el).children('form').serializeObject(), {
        success: function(){ el.removeClass('loading'); panel.addUser(model); },
        error: function(){ console.log('ERROR');}
      });
    },

    render: function() {
      var el = $(this.el).empty();
      
      var form = el.append('<form></form>').children().last();
      //form.append('<input name="_method" value="post"/>');
      form.append(this.template());
      
      return this;
    }

  });

  var BanListPanel = Backbone.View.extend({
    tagName: 'div',
    id: 'banedit',

    events: {
      "click a.add_ban": 'createBan'
    },
    
    initialize: function() {
      BanList.bind('add', this.addBan, this);
      BanList.bind('reset', this.addBans, this);
      //UserList.bind('all', this.render, this);
      
      BanList.fetch();
    },
    
    // Create user view
    addBan: function(ban) {
      var view = new BanListRow({model: ban});
      $('#banedit').append(view.render().el);
    },
    
    addBans: function(bans) {
      bans.each(this.addBan);
    },
    
    // Opens the user form
    createBan: function() {
      if ($('#banedit').find('.user_form')[0])
        return;
      var form = new NewBanForm({model: new AdminBan({})});
      $('#banedit').prepend(form.render().el);
    },

    render: function() {
      var el = $(this.el).empty();
      el.append('<a href="#" class="add_ban">' + 'Add Ban' + '</a>');
      return this;
    }

  });

  // Navigation
  var AdminPanelController = Backbone.Router.extend({

    routes: {
      "":                      "index",
      "admin/users":           "users",
      "admin/bans":            "bans",
      "admin/channels":        "channels"
    },

    setTab: function(tabName) {
      console.log('setTab',tabName);
      $('#tabsWrapper ul li a').removeClass('active');
      $('#tabsWrapper ul #tab_' + tabName + ' a').addClass('active');
    },

    clearPanel: function() {
      if (panel) {
        panel.unbind();
        panel.remove();
      }
    },

    index: function() {
      this.clearPanel();
      this.setTab('admin_home');
    },

    bans: function(query, page) {
      //
      this.clearPanel();
      this.setTab('admin_bans');

      panel = new BanListPanel();
      $('#adminroot').empty().append(panel.render().el);
    },

    channels: function(query, page) {
      //
      this.clearPanel();
      this.setTab('admin_channels');

      panel = new ChannelListPanel();
      $('#adminroot').empty().append(panel.render().el);
    },

    users: function(query, page) {
      //
      this.clearPanel();
      this.setTab('admin_users');

      panel = new UserListPanel();
      $('#adminroot').empty().append(panel.render().el);
    }

  });

  Tube.makeAdmin = function(root) {
    router = new AdminPanelController();
    Backbone.history.start({pushState: true});
    
    $('#tabsWrapper li a').on("click", function(event){
      event.preventDefault();
      console.log('NAV',$(this).attr('href').substring(1));
      router.navigate($(this).attr('href').substring(1), {trigger: true});
    });
  };


})();