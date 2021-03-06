// Place all the behaviors and hooks related to the matching controller here.
// All this logic will automatically be available in application.js.

// TODO
// - error handling of assigning user to project, check XHR data.errors
// - error handling of removing user from project, check XHR data.errors
// - refresh project users tab after manage user modal is closed
// - refactor view handling using library, ex. backbone.js

(function () {

  var newProjectModal = null;
  var newProjectModalForm = null;
  var newProjectBtn = null;

  var editProjectModal = null;
  var editProjectModalTitle = null;
  var editProjectModalForm = null;
  var editProjectBtn = null;

  var manageUsersModal = null;
  var manageUsersModalBody = null;

  /**
   * Stupid Bootstrap btn-group bug hotfix
   * @param btnGroup - The button group element.
   */
  function activateBtnGroup(btnGroup) {
    var btns = btnGroup.find(".btn");
    btns.find("input[type='radio']")
    .removeAttr("checked")
    .prop("checked", false);
    btns.filter(".active")
    .find("input[type='radio']")
    .attr("checked", "checked")
    .prop("checked", true);
  }

  /**
   * Initialize the JS for new project modal to work.
   */
  function initNewProjectModal() {
    newProjectModalForm.submit(function() {
      // Stupid Bootstrap btn-group bug hotfix
      activateBtnGroup(
        newProjectModal
        .find("form .btn-group[data-toggle='buttons']")
      );
    });
    newProjectModal.on("hidden.bs.modal", function () {
      // When closing the new project modal, clear its input vals
      // and potential errors
      newProjectModalForm.clear_form_errors();

      // Clear input fields
      newProjectModalForm.clear_form_fields();
      var orgSelect = newProjectModalForm.find('select#project_organization_id');
      orgSelect.val(0);
      orgSelect.selectpicker('refresh');

      var orgHidden = newProjectModalForm.find('input#project_visibility_hidden');
      var orgVisible = newProjectModalForm.find('input#project_visibility_visible');
      orgHidden.prop("checked", true);
      orgHidden.attr("checked", "checked");
      orgHidden.parent().addClass("active");
      orgVisible.prop("checked", false);
      orgVisible.parent().removeClass("active");
    })
    .on("show.bs.modal", function() {
      var orgSelect = newProjectModalForm.find('select#project_organization_id');
      orgSelect.selectpicker('refresh');
    });

    newProjectModalForm
    .on("ajax:success", function(data, status, jqxhr) {
      // Redirect to response page
      $(location).attr("href", status.url);
    })
    .on("ajax:error", function(jqxhr, status, error) {
      $(this).render_form_errors("project", status.responseJSON);
    });

    newProjectBtn.click(function(e) {
      // Show the modal
      newProjectModal.modal("show");
      return false;
    });
  }

  /**
   * Initialize the JS for edit project modal to work.
   */
  function initEditProjectModal() {
    // Edit button click handler
    editProjectBtn.click(function() {
      // Stupid Bootstrap btn-group bug hotfix
      activateBtnGroup(
        editProjectModalBody
        .find("form .btn-group[data-toggle='buttons']")
      );

      // Submit the modal body's form
      editProjectModalBody.find("form").submit();
    });

    // On hide modal handler
    editProjectModal.on("hidden.bs.modal", function() {
      editProjectModalBody.html("");
    });

    $(".panel-project a[data-action='edit']")
    .on("ajax:success", function(ev, data, status) {
      // Update modal title
      editProjectModalTitle.html(data.title);

      // Set modal body
      editProjectModalBody.html(data.html);

      // Add modal body's submit handler
      editProjectModal.find("form")
      .on("ajax:success", function(ev2, data2, status2) {
        // Project saved, replace changed project's title
        var responseHtml = $(data2.html);
        var id = responseHtml.attr("data-id");
        var newTitle = responseHtml.find(".panel-title");
        var existingTitle =
          $(".panel-project[data-id='" + id + "'] .panel-title");

        existingTitle.after(newTitle);
        existingTitle.remove();

        // Hide modal
        editProjectModal.modal("hide");
      })
      .on("ajax:error", function(ev2, data2, status2) {
        $(this).render_form_errors("project", data2.responseJSON);
      });

      // Show the modal
      editProjectModal.modal("show");
    })
    .on("ajax:error", function(ev, data, status) {
      // TODO
    });
  }

  function initManageUsersModal() {
    // Reload users tab HTML element when modal is closed
    manageUsersModal.on("hide.bs.modal", function () {
      var projectEl = $("#" + $(this).attr("data-project-id"));

      // Load HTML to refresh users list
      $.ajax({
        url: projectEl.attr("data-project-users-tab-url"),
        type: "GET",
        dataType: "json",
        success: function (data) {
          projectEl.find("#users-" + projectEl.attr("id")).html(data.html);
          initUsersEditLink(projectEl);
        },
        error: function (data) {
          // TODO
        }
      });
    });

    // Remove modal content when modal window is closed.
    manageUsersModal.on("hidden.bs.modal", function () {
      manageUsersModalBody.html("");
    });
  }

  // Initialize users editing modal remote loading.
  function initUsersEditLink($el) {

     $el.find(".manage-users-link")

       .on("ajax:before", function () {
        var projectId = $(this).closest(".panel-default").attr("id");
          manageUsersModal.attr("data-project-id", projectId);
          manageUsersModal.modal('show');
       })

       .on("ajax:success", function (e, data) {
         $("#manage-users-modal-project").text(data.project.name);
         initUsersModalBody(data);
       });
  }

  // Initialize comment form.
  function initCommentForm($el) {

    var $form = $el.find("ul form");

    $(".help-block", $form).addClass("hide");

    $form.on("ajax:send", function (data) {
      $("#comment_message", $form).attr("readonly", true);
    })
    .on("ajax:success", function (e, data) {
      if (data.html) {
        var list = $form.parents("ul");

        // Remove potential "no comments" element
        list.parent().find(".content-comments")
          .find("li.no-comments").remove();

        list.parent().find(".content-comments")
          .prepend("<li class='comment'>" + data.html + "</li>")
          .scrollTop(0);
        list.parents("ul").find("> li.comment:gt(8)").remove();
        $("#comment_message", $form).val("");
        $(".form-group", $form)
          .removeClass("has-error");
        $(".help-block", $form)
            .html("")
            .addClass("hide");
      }
    })
    .on("ajax:error", function (ev, xhr) {
      if (xhr.status === 400) {
        var messageError = xhr.responseJSON.errors.message;

        if (messageError) {
          $(".form-group", $form)
            .addClass("has-error");
          $(".help-block", $form)
              .html(messageError[0])
              .removeClass("hide");
        }
      }
    })
    .on("ajax:complete", function () {
      $("#comment_message", $form)
        .attr("readonly", false)
        .focus();
    });
  }

  // Initialize show more comments link.
  function initCommentsLink($el) {

    $el.find(".btn-more-comments")
      .on("ajax:success", function (e, data) {
        if (data.html) {
          var list = $(this).parents("ul");
          var moreBtn = list.find(".btn-more-comments");
          var listItem = moreBtn.parents('li');
          $(data.html).insertBefore(listItem);
          if (data.results_number < data.per_page) {
            moreBtn.remove();
          } else {
            moreBtn.attr("href", data.more_url);
          }
        }
      });
  }

  // Initialize reloading manage user modal content after posting new
  // user.
  function initAddUserForm() {

    manageUsersModalBody.find(".add-user-form")

      .on("ajax:success", function (e, data) {
        initUsersModalBody(data);
        if (data.status === 'error') {
          $(this).addClass("has-error");
          $(this).append("<span class='help-block col-xs-8'>" + data.error + "</span>");
        }
      });
  }

  // Initialize remove user from project links.
  function initRemoveUserLinks() {

    manageUsersModalBody.find(".remove-user-link")

      .on("ajax:success", function (e, data) {
        initUsersModalBody(data);
      });
  }

  //
  function initUserRoleForms() {

    manageUsersModalBody.find(".update-user-form select")

      .on("change", function () {
        $(this).parents("form").submit();
      });

    manageUsersModalBody.find(".update-user-form")

      .on("ajax:success", function (e, data) {
        initUsersModalBody(data);
      })

      .on("ajax:error", function (e, xhr, status, error) {
        // TODO
      });
  }

  // Initialize ajax listeners and elements style on modal body. This
  // function must be called when modal body is changed.
  function initUsersModalBody(data) {
    manageUsersModalBody.html(data.html);
    manageUsersModalBody.find(".selectpicker").selectpicker();
    initAddUserForm();
    initRemoveUserLinks();
    initUserRoleForms();
  }


  function init() {

    newProjectModal = $("#new-project-modal");
    newProjectModalForm = newProjectModal.find("form");
    newProjectBtn = $("#new-project-btn");

    editProjectModal = $("#edit-project-modal");
    editProjectModalTitle = editProjectModal.find("#edit-project-modal-label");
    editProjectModalBody = editProjectModal.find(".modal-body");
    editProjectBtn = editProjectModal.find(".btn[data-action='submit']");

    manageUsersModal = $("#manage-users-modal");
    manageUsersModalBody = manageUsersModal.find(".modal-body");

    initNewProjectModal();
    initEditProjectModal();
    initManageUsersModal();

    // initialize project tab remote loading
    $(".panel-project .panel-footer [role=tab]")

      .on("ajax:before", function (e) {
        var $this = $(this);
        var parentNode = $this.parents("li");
        var targetId = $this.attr("aria-controls");

        if (parentNode.hasClass("active")) {
          // TODO move to fn
          parentNode.removeClass("active");
          $("#" + targetId).removeClass("active");
          return false;
        }
      })

      .on("ajax:success", function (e, data, status, xhr) {

        var $this = $(this);
        var targetId = $this.attr("aria-controls");
        var target = $("#" + targetId);
        var parentNode = $this.parents("ul").parent();

        target.html(data.html);
        initUsersEditLink(parentNode);
        initCommentForm(parentNode);
        initCommentsLink(parentNode);

        // TODO move to fn
        parentNode.find(".active").removeClass("active");
        $this.parents("li").addClass("active");
        target.addClass("active");
      })

      .on("ajax:error", function (e, xhr, status, error) {
        // TODO
      });

    // Initialize first-time tutorial
    if (Cookies.get('tutorial_data')) {
      var tutorialData = JSON.parse(Cookies.get('tutorial_data'));
      var goToStep = 1;
      var demoProjectId = tutorialData[0].project;
      if (Cookies.get('current_tutorial_step')) {
        goToStep = parseInt(Cookies.get('current_tutorial_step'));
      }
      if (goToStep < 4) {
        var projectOptionsTutorial = $("#projects-toolbar").attr("data-project-options-step-text");
        var demoProject = $("#" + demoProjectId);
        demoProject.attr('data-step', '3');
        demoProject.attr('data-intro', projectOptionsTutorial);
        demoProject.attr('data-position', 'left');
        demoProject.attr('data-tooltipClass', 'custom disabled-next');

        introJs()
          .setOptions({
            overlayOpacity: '0.2',
            nextLabel: 'Next',
            doneLabel: 'End tutorial',
            skipLabel: 'End tutorial',
            showBullets: false,
            showStepNumbers: false,
            tooltipClass: 'custom'
          })
          .goToStep(goToStep)
          .onafterchange(function (tarEl) {
            Cookies.set('current_tutorial_step', this._currentStep+1);
          })
          .start();

        // Destroy first-time tutorial cookies when skip tutorial
        // or end tutorial is clicked
        $(".introjs-skipbutton").each(function (){
          $(this).click(function (){
            Cookies.remove('tutorial_data');
            Cookies.remove('current_tutorial_step');
          });
        });
      }
      else if (goToStep > 11) {
        var archiveProjectTutorial = $("#projects-toolbar").attr("data-archive-project-step-text");
        Cookies.set('current_tutorial_step', '13');

        introJs()
          .setOptions({
            steps: [{
              element: document.getElementById(demoProjectId),
              intro: archiveProjectTutorial,
              position: "right"
            }],
            overlayOpacity: '0.2',
            doneLabel: 'Start using sciNote',
            showBullets: false,
            showStepNumbers: false,
            disableInteraction: false,
            tooltipClass: 'custom disabled-next'
          })
          .oncomplete(function () {
            Cookies.remove('tutorial_data');
            Cookies.remove('current_tutorial_step');
          })
          .start();
      }
    }
  }

  init();
}());