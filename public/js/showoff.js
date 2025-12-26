// Showoff client-side code
var ShowoffTracker = { };

// Custom slide navigation system to replace jQuery Cycle
var SlideSystem = {
  // Current slide index
  currentSlide: 0,

  // Total number of slides
  slideCount: 0,

  // Transition type (fade, none, slide)
  transition: 'fade',

  // Initialize the slide system
  init: function(options) {
    options = options || {};
    this.transition = options.transition || 'fade';

    // Set transition class on container
    $('#preso').addClass('transition-' + this.transition);

    // Get all slides
    var slides = $('#preso > .slide');
    this.slideCount = slides.length;

    // Hide all slides initially
    slides.removeClass('slide-active').addClass('slide-inactive');

    // Show the first slide
    if (this.slideCount > 0) {
      $(slides[0]).removeClass('slide-inactive').addClass('slide-active');
      this.currentSlide = 0;
    }

    return this;
  },

  // Go to a specific slide
  goTo: function(slideNum) {
    if (slideNum < 0 || slideNum >= this.slideCount) {
      return false;
    }

    var slides = $('#preso > .slide');
    var currentSlide = slides.eq(this.currentSlide);
    var targetSlide = slides.eq(slideNum);

    // Remove active class from current slide
    currentSlide.removeClass('slide-active').addClass('slide-inactive');

    // Add active class to target slide
    targetSlide.removeClass('slide-inactive').addClass('slide-active');

    // Update current slide index
    this.currentSlide = slideNum;

    // Trigger an event for other components
    $('#preso').trigger('slide-update-view');

    return true;
  },

  // Go to the next slide
  next: function() {
    var nextSlide = (this.currentSlide + 1) % this.slideCount;
    return this.goTo(nextSlide);
  },

  // Go to the previous slide
  prev: function() {
    var prevSlide = (this.currentSlide - 1 + this.slideCount) % this.slideCount;
    return this.goTo(prevSlide);
  },

  // Resume (no-op for compatibility)
  resume: function() {
    // jQuery Cycle had a resume function, but we don't need it
    // Keep it for API compatibility
    return true;
  }
};

function setupPreso(load_slides, prefix) {
  if (typeof(prefix) == 'undefined') {
    prefix = '';
  }

  if (typeof(load_slides) == "undefined") {
    load_slides = false;
  }

  paceMarker = $('#paceMarker');
  center     = $('#center');
  slides     = $('#slides');

  //load slides offscreen, wait for images and then initialize
  if (load_slides) {
    $("#slides").load(prefix + "slides", false, function(){
      $("#slides img").batchImageLoad({
        loadingCompleteCallback: initializePresentation(prefix)
      });
    });
  } else {
    $("#slides img").batchImageLoad({
      loadingCompleteCallback: initializePresentation(prefix)
    });
  }
}

function initializePresentation(prefix) {
  // unhide for height to work in static mode
  $("#slides").show();

  //center slides offscreen
  centerSlides($('#slides > .slide'));

  //copy into presentation area
  $("#preso").empty();
  $('#slides > .slide').appendTo($("#preso"));

  //populate vars
  slides = $('#preso > .slide');
  slideTotal = slides.length;

  //setup custom slide system
  SlideSystem.init();

  setupMenu();
  if (slidesLoaded) {
    showSlide();
  } else {
    showFirstSlide();
    slidesLoaded = true;
  }
  setupSlideParamsCheck();

  if(navigator.userAgent.match(/iPhone/i) || navigator.userAgent.match(/iPod/i) || navigator.userAgent.match(/iPad/i)) {
    expandContent();
    $('body').addClass('mobile');
  }

  $(".slide.commandline pre.term").each(function(index) {
    $(this).addClass("ui-corner-all");
    $(this).prepend('<div class="buttons"></div>');
    $(this).find('.buttons').append('<div class="close"></div>');
    $(this).find('.buttons').append('<div class="minimize"></div>');
    $(this).find('.buttons').append('<div class="maximize"></div>');
  });

  setupSideMenu();
  setupAnnotations();
  setupTouchEvents();

  // Open up our control socket
  if( typeof(socketUrl) != 'undefined' ) {
    connectControlChannel(socketUrl);
  }

  $(document).keydown(keyDown);
  $(document).keyup(keyUp);

  // Give us the ability to disable the help on a per-slide basis with data-help='false'
  $('.slide').each(function() {
    if($(this).attr('data-help') === 'false') {
      $(this).find('.help').remove();
    }
  });

  // Make sure the slides always get focus.
  slides.click(function(e) {
    if(e.target.nodeName == 'TEXTAREA' || e.target.nodeName == 'INPUT') {
      return true;
    } else {
      slidenum = slides.index($(this));
      gotoSlide(slidenum);
      return false;
    }
  });

  // left arrow, page up, shift-space
  Mousetrap.on(['left', 'pageup', 'shift+space'], function(e) {
    prevStep();
    return false;
  });

  // right arrow, page down, space
  Mousetrap.on(['right', 'pagedown', 'space'], function(e) {
    nextStep();
    return false;
  });

  // p for presenter view
  Mousetrap.on('p', function(e) {
    togglePresenterView();
    return false;
  });

  // P for private notes
  Mousetrap.on('P', function(e) {
    togglePrivateNotes();
    return false;
  });

  // c for copy of notes
  Mousetrap.on('c', function(e) {
    try {
      var notes = getCurrentNotes();
      navigator.clipboard.writeText(notes).then(function() {
        console.log('Content copied to clipboard');
        /* success */
      }, function() {
        console.log('Failed to copy');
        /* failure */
      });
    } catch(e) {
      console.log('Failed to copy');
      console.log(e);
    }
    return false;
  });

  // f for footer
  Mousetrap.on('f', function(e) {
    toggleFooter();
    return false;
  });

  // h for help
  Mousetrap.on('h', function(e) {
    toggleHelp();
    return false;
  });

  // n for notes
  Mousetrap.on('n', function(e) {
    toggleSlideNotes();
    return false;
  });

  // s for style
  Mousetrap.on('s', function(e) {
    toggleStyle();
    return false;
  });

  // z for zoom
  Mousetrap.on('z', function(e) {
    toggleZoom();
    return false;
  });

  // i for inkscape on an svg slide
  Mousetrap.on('i', function(e) {
    inkscapeView();
    return false;
  });

  // b for blank, white screen
  Mousetrap.on('b', function(e) {
    blankScreen();
    return false;
  });

  // Unset the generated 'Mousetrap' class
  $('.mousetrap').removeClass('mousetrap');

  // Sync the stage to the slide the presenter is on
  postSlide();

  // Explicitly call resize() to make sure that all slides
  // are properly aligned in the window.
  $(window).resize();

  // Hook up Mermaid diagrams
  mermaid.initialize({startOnLoad:true});
  mermaid.init(undefined, ".mermaid");

  // Bind to events for the presenter view
  if( typeof(presenterView) != 'undefined' ) {
    var currentSlide = 0;
    var iframe = document.getElementById("nextSlide");
    var iframeWin = iframe.contentWindow || iframe;
    var nextSlideEvents = ["next", "prev"];
    for(var i = 0; i < nextSlideEvents.length; i++) {
      var eventName = nextSlideEvents[i];
      iframeWin.addEventListener("showoff:slide:"+eventName, function(e) {
        var slide = e.detail.slide;
        if(slide != currentSlide) {
          currentSlide = slide;
          var nextSlideNum = (currentSlide + 1) % slideTotal;
          var nextSlide = slides.eq(nextSlideNum);
          var notes = nextSlide.find("div.notes");
          var notesText = notes.text();
          if(notesText == '') {
            notesText = nextSlide.find("div.notes-section").text();
          }
          if(notesText == '') {
            notesText = I18n.t('presenter.nonotes');
          }
          $("#notesText").text(notesText);
        }
      });
    }
  }
}

function centerSlides(slides) {
  slides.each(function(s, slide) {
    centerSlide(slide);
  });
}

function centerSlide(slide) {
  var slide_content = $(slide).find(".content").first();
  var height = slide_content.height();
  var mar_top = (0.5 * parseFloat($(slide).height())) - (0.5 * parseFloat(height));
  if (mar_top < 0) {
    mar_top = 0;
  }
  slide_content.css('margin-top', mar_top);
}

function setupMenu() {
  $('#navmenu').hide();

  var menuHTML = '';
  var slidesHTML = '';

  slides.each(function(s, slide) {
    var slideTitle = $(slide).find(".content").find("h1").text();
    if (slideTitle) {
      menuHTML += '<div class="menu-toc-list"><a class="menu-toc-link" href="#' + (s+1) + '"><span class="menu-toc-slide-number">' + (s+1) + '.</span><span class="menu-toc-slide-title">' + slideTitle + '</span></a></div>';
      slidesHTML += '<div class="menu-slide-link"><a class="menu-slide-number" href="#' + (s+1) + '">' + (s+1) + '</a></div>';
    }
  });

  $('#navigation').html(slidesHTML);
  $('#menu-toc').html(menuHTML);

  $('#menu-toc .menu-toc-link').click(function(e) {
    e.preventDefault();
    gotoSlide(parseInt($(this).attr('href').substr(1) - 1));
    toggleSideMenu();
  });

  $('#navigation .menu-slide-number').click(function(e) {
    e.preventDefault();
    gotoSlide(parseInt($(this).attr('href').substr(1) - 1));
    toggleSideMenu();
  });

  $("#close-menu").click(function() {
    toggleSideMenu();
  });

  // include the language selector if we have multiple languages
  if(typeof(cookieLanguage) != 'undefined') {
    var langDrop = $("#language-dropdown");
    langDrop.empty();
    for(var i=0; i < languages.length; i++) {
      var lang = languages[i];
      langDrop.append('<li><a href="javascript:setLanguage(\''+lang+'\')" class="'+lang+'">'+lang+'</a></li>');
    }
  }
}

function setupSideMenu() {
  $("#hamburger").click(function() {
    toggleSideMenu();
  });
}

function toggleSideMenu() {
  if($("#sideMenu").is(':visible')) {
    $("#sideMenu").hide();
    $("#main").css("margin-left", "0");
    $("#main").css("padding-left", "10px");
    $("#hamburger").css("margin-left", "0");
  }
  else {
    $("#sideMenu").show();
    $("#main").css("margin-left", "240px");
    $("#main").css("padding-left", "20px");
    $("#hamburger").css("margin-left", "240px");
  }
}

function toggleZoom() {
  if($("#preso").hasClass('zoomed')) {
    $("#preso").removeClass('zoomed');
    $("#zoomer").hide();
  }
  else {
    $("#preso").addClass('zoomed');
    $("#zoomer").show();
  }
}

function blankScreen() {
  if($("body").hasClass('blanked')) {
    $("body").removeClass('blanked');
  }
  else {
    $("body").addClass('blanked');
  }
}

function inkscapeView() {
  if($("#preso").hasClass('inkscaped')) {
    $("#preso").removeClass('inkscaped');
    $("#main").show();
    $("#hamburger").show();
  }
  else {
    $("#preso").addClass('inkscaped');
    $("#main").hide();
    $("#hamburger").hide();
  }
}

function setupTouchEvents() {
  var orgX, newX;
  var tracking = false;

  var db = document.body;
  db.addEventListener("touchstart", start, false);
  db.addEventListener("touchmove", move, false);

  function start(e) {
    orgX = e.changedTouches[0].pageX;
    tracking = true;
  }

  function move(e) {
    if(!tracking) return;
    newX = e.changedTouches[0].pageX;
    if(orgX - newX > 100) {
      tracking = false;
      nextStep();
    } else {
      if(orgX - newX < -100) {
        tracking = false;
        prevStep();
      }
    }
  }
}

function setupSlideParamsCheck() {
  var hash = window.location.hash;
  if (hash !== "") {
    var ss = hash.substr(1);
    if (typeof(slideParam[ss]) != 'undefined') {
      gotoSlide(slideParam[ss]);
    } else if (ss.match(/^[0-9]+$/)) {
      gotoSlide(parseInt(ss) - 1);
    }
  }
}

function getSlideProgress() {
  var current = currentSlideFromParams();
  if(current) {
    return current + '/' + slideTotal;
  }
  return (slidenum + 1) + '/' + slideTotal
}

function currentSlideFromParams() {
  var hash = window.location.hash;
  if (hash == "") {
    return null;
  }
  return parseInt(hash.substr(1));
}

function toggleFooter() {
  $('#footer').toggle();
}

function toggleHelp() {
  $('#help').toggle();
}

function togglePresenterView() {
  $('#presenter-view').toggle();
}

function togglePrivateNotes() {
  $('#private-notes').toggle();
}

function toggleSlideNotes() {
  $('#notes').toggle();
}

function setLanguage(lang) {
  cookieLanguage = lang;
  document.cookie = "language=" + lang;
  location.reload();
}

function toggleStyle() {
  $('link[rel="stylesheet"]').map(function() {
    var href = $(this).attr('href');
    var re = new RegExp("styles/([^\/]+)\.css");
    var arr = re.exec(href);
    if(arr && arr.length > 1) {
      var style = arr[1];
      var newStyle;
      if(style == 'primary') {
        newStyle = 'secondary';
      }
      else {
        newStyle = 'primary';
      }
      $(this).attr('href', 'styles/'+newStyle+'.css');
    }
  });
}

function showSlide(back_step, incr) {

  // allows the back_step parameter to be optional
  if (typeof(back_step) == 'undefined') {
    back_step = false;
  }
  if (typeof(incr) == 'undefined') {
    incr = 0;
  }

  // remember where we should be
  slidenum = parseInt(slidenum) + incr;

  // before going to the next slide, set up our call to showSlide for after this slide loads
  if(incr > 0) {
    $("#preso").on("slide-before", function(e, opts) {
      var nextS = $(e.target).find("div.slide").eq(opts.nextSlide);
      $(nextS).on("slide-added", function() {
        $(nextS).off("slide-added");
        showSlide(true);
      });
    });
  }

  // load the slide content
  loadSlideContent();

  // navigate to slide
  SlideSystem.goTo(slidenum);

  if (back_step) {
    $(".incremental").each(function() {
      var elem = $(this);
      if (elem.hasClass('to-show') || elem.hasClass('to-hide')) {
        elem.removeClass('to-show');
        elem.removeClass('to-hide');
        elem.addClass('hidden');
      }
    });
  }

  slidenum = $("#preso").find('.slide.slide-active').attr('snum');
  if(!back_step) {
    // update slide state
    showSlideNumbers(slidenum);
    loadSlideContent();
    postSlide();
  }

  // copy slide content to presenter view
  if(typeof(presenterView) != 'undefined') {
    var pv = $("#presenterView");
    var title = $("#preso .slide.slide-active h1").text();
    pv.find(".preso-title").text(title);
    var notes = getCurrentNotes();
    pv.find(".preso-notes").text(notes);
  }

  // Update presenter view, if we spawned one
  if (typeof(slaveWindow) != 'undefined' && slaveWindow != null) {
    // set the notes for this slide in the presenter view
    var notes = getCurrentNotes();
    slaveWindow.postMessage('notes:'+notes, '*');
  }

  // Update presenter view, if we are a slave
  if(typeof(master) != 'undefined' && master == false) {
    var notes = getCurrentNotes();
    var detail = {slide: slidenum, notes: notes};
    window.parent.postMessage('notes:'+notes, '*');
    window.parent.postMessage('slide:'+slidenum, '*');
    window.parent.postMessage('slideEvent:showoff:slide:next', '*');
  }

  // Update presenter view, if we are a master
  if(typeof(presenterView) != 'undefined') {
    var iframe = document.getElementById("nextSlide");
    var iframeWin = iframe.contentWindow || iframe;
    var detail = {slide: slidenum};
    iframeWin.postMessage('showoff:slide:next', '*', detail);
  }

  $("#paceMarker").fadeOut();
}

function getCurrentNotes() {
  var notes = $("#preso .slide.slide-active div.notes").text();
  if(notes == '') {
    notes = $("#preso .slide.slide-active div.notes-section").text();
  }
  if(notes == '') {
    notes = I18n.t('presenter.nonotes');
  }
  return notes;
}

function showSlideNumbers(num) {
  $('#slideInfo').text((num+1) + '/' + slideTotal);
  if(typeof(presenterView) != 'undefined') {
    var pv = $("#presenterView");
    pv.find(".slideInfo").text((num+1) + '/' + slideTotal);
  }
}

function loadSlideContent() {
  var url = loadSlideUrl();
  if(url) {
    var slide = $("#preso .slide.slide-active");
    slide.load(url, function() {
      slide.find('pre.highlight code').each(function(i, e) {
        hljs.highlightElement(e);
        hljs.lineNumbersBlock(e);
      });
      centerSlide(slide);
      mermaid.init(undefined, ".mermaid");
    });
  }
}

function loadSlideUrl() {
  var slide = $("#preso .slide.slide-active");
  var url = slide.attr('ref');
  if(url) {
    if(url.match(/^http/)) {
      slide.find('iframe').attr('src', url);
      return null;
    }
    else {
      return url;
    }
  }
  return null;
}

function runCode(lang, codeDiv) {
  var result;

  setExecutionSignal(true, codeDiv);
  setTimeout(function() { setExecutionSignal(false, codeDiv);}, 1000 );

  try {
    switch(lang) {
      case 'javascript':
        result = eval(codeDiv.text());
        break;
      case 'coffeescript':
        // Use CoffeeScript 2.7.0 if available, fall back to 1.1.3 if not
        if (typeof CoffeeScript !== 'undefined') {
          result = eval(CoffeeScript.compile(codeDiv.text(), {bare: true}));
        } else {
          console.error("CoffeeScript compiler not available");
          result = "CoffeeScript compiler not available";
        }
        break;
      default:
        result = 'No local exec handler for ' + lang;
    }
  }
  catch(e) {
    result = e.message;
  };
  if (result != null) displayHUD(result);
}

// request the server to execute a code block by path and index
function executeRemoteCode(lang, codeDiv) {
  var slide = codeDiv.closest('div.content');
  var index = slide.find('code.execute').index(codeDiv);
  var path  = slide.attr('ref');

  setExecutionSignal(true, codeDiv);
  $.get('execute/'+lang, {path: path, index: index}, function(result) {
    displayHUD(result);
    setExecutionSignal(false, codeDiv);
  });
}

function setExecutionSignal(status, codeDiv) {
  if (status === true) {
    codeDiv.addClass("executing");
  }
  else {
    codeDiv.removeClass("executing");
  }
}

function displayHUD(text) {
  $('#HUD').html(text);
  $('#HUD').show();
  setTimeout(function() { $('#HUD').hide(); }, 5000);
}

function prevStep(updatepv)
{
  var curr = currentSlideFromParams();
  var currentIncr = 0;

  if(curr) {
    var s = $("#preso .slide:eq("+(curr-1)+")");
    if(s.hasClass('incremental')) {
      var vis = s.find('.incremental:visible');
      var visslide = s.find('.incremental.slide:visible');
      if(visslide.length > 0) {
        currentIncr = visslide.attr('value');
      }
      else if(vis.length > 0) {
        currentIncr = vis.last().attr('value');
      }
    }
  }

  var preso = $("#preso");
  preso.off("slide-before");

  var currentSlide = $('.slide.slide-active');
  var increment = currentSlide.find('.incremental');

  var incrs = increment.filter(function() {
    return $(this).attr('value') == currentIncr;
  });

  // when displaying with 'fade' transition, we need to actually go to the slide
  // and hide the increments, rather than cycling which just shows/hides the slide
  if(currentIncr > 0) {
    // remove the class from all incrementals that have it
    incrs.removeClass('to-show');
    incrs.removeClass('to-hide');
    incrs.addClass('hidden');

    // now find incrementals with lower value
    var prevIncrs = increment.filter(function() {
      return $(this).attr('value') < currentIncr;
    });
    prevIncrs.removeClass('hidden');
    prevIncrs.addClass('to-hide');

    var prevIncr = currentIncr - 1;
    var newIncrs = increment.filter(function() {
      return $(this).attr('value') == prevIncr;
    });
    if(newIncrs.length > 0) {
      newIncrs.removeClass('hidden');
      newIncrs.addClass('to-show');
    }
    else {
      // no previous increments, go to previous slide
      SlideSystem.prev();
    }
  }
  else {
    SlideSystem.prev();
  }

  if (typeof(updatepv) == 'undefined') {
    updatepv = true;
  }

  if (updatepv) {
    var postSlideContent = postSlide;
    // transition to the previous slide
    postSlide = function() {
      $("#preso").off('slide-update-view', postSlide);
      postSlide = postSlideContent;
      postSlideContent();
    };
    $("#preso").on('slide-update-view', postSlide);
  }
}

function nextStep(updatepv)
{
  var curr = currentSlideFromParams();
  var currentIncr = 0;

  if(curr) {
    var s = $("#preso .slide:eq("+(curr-1)+")");
    if(s.hasClass('incremental')) {
      var vis = s.find('.incremental:visible');
      var visslide = s.find('.incremental.slide:visible');
      if(visslide.length > 0) {
        currentIncr = visslide.attr('value');
      }
      else if(vis.length > 0) {
        currentIncr = vis.last().attr('value');
      }
    }
  }

  var currentSlide = $('.slide.slide-active');
  var increment = currentSlide.find('.incremental');

  var currentVisible = increment.filter(function() {
    return $(this).hasClass('to-show') || $(this).hasClass('to-hide');
  });
  if(currentVisible.length == 0) {
    // nothing shown yet, so show first set
    var firstIncrs = increment.filter(function() {
      return $(this).attr('value') == 0;
    });
    if(firstIncrs.length > 0) {
      increment.filter(function() {
        return $(this).attr('value') == 0;
      }).removeClass('hidden').addClass('to-show');
    }
    else {
      var preso = $("#preso");
      preso.off("slide-before");
      SlideSystem.next();
    }
  }
  else {
    // show the next set
    var nextIncr = currentIncr + 1;
    var newIncrs = increment.filter(function() {
      return $(this).attr('value') == nextIncr;
    });
    if(newIncrs.length > 0) {
      newIncrs.removeClass('hidden').addClass('to-show');
      currentVisible.removeClass('to-show').addClass('to-hide');
    }
    else {
      var preso = $("#preso");
      preso.off("slide-before");
      SlideSystem.next();
    }
  }

  if (typeof(updatepv) == 'undefined') {
    updatepv = true;
  }

  if (updatepv) {
    var postSlideContent = postSlide;
    // transition to the next slide
    postSlide = function() {
      $("#preso").off('slide-update-view', postSlide);
      postSlide = postSlideContent;
      postSlideContent();
    };
    $("#preso").on('slide-update-view', postSlide);
  }
}

function doDebugStuff()
{
  if (debugMode) {
    $('#debugInfo').show();
    debug('debug mode on');
  } else {
    $('#debugInfo').hide();
  }
}

function debug(data)
{
  $('#debugInfo').text(data);
  console.log(data);
}

function toggleDebug()
{
  debugMode = !debugMode;
  doDebugStuff();
}

function showNext() {
  nextStep();
}

function showPrev() {
  prevStep();
}

function doSlide(slideNum) {
  gotoSlide(parseInt(slideNum));
}

function gotoSlide(slideNum, updatepv) {
  var preso = $("#preso");
  preso.off("slide-before");
  SlideSystem.goTo(slideNum);

  if (typeof(updatepv) == 'undefined') {
    updatepv = true;
  }

  if (updatepv) {
    var postSlideContent = postSlide;
    // transition to the next slide
    postSlide = function() {
      $("#preso").off('slide-update-view', postSlide);
      postSlide = postSlideContent;
      postSlideContent();
    };
    $("#preso").on('slide-update-view', postSlide);
  }
}

function showFirstSlide() {
  gotoSlide(0);
  showSlide();
}

function showSlideById(id) {
  gotoSlide(parseInt(slides.index($('#'+id))));
  showSlide();
}

function postSlide() {
  if(currentSlideFromParams() == null) {
    var slide = slides.eq(slidenum);
    var id = slide.attr('id');
    if (typeof(id) != 'undefined') {
      window.location.hash = '#' + id;
    } else {
      window.location.hash = '#' + (slidenum+1);
    }
  }
  SlideSystem.resume();
}

function expandSlide() {
  $("#preso").height("100%");
  $("#preso").width("100%");
}

function unexpandSlide() {
  $("#preso").height("620px");
  $("#preso").width("800px");
}

function toggleSlide() {
  if ($("#preso").height() == "620px") {
    expandSlide();
  }
  else {
    unexpandSlide();
  }
}

function notesWindow() {
  try {
    var opts = {
      toolbar: false,
      resizable: false,
      scrollbars: true,
      height: 640,
      width: 800
    };

    var url = 'notes';
    slaveWindow = window.open(url, 'showoff_notes', opts);
    slaveWindow.focus();
  }
  catch(e) {
    console.log('Failed to open notes window. ' + e.message);
  }
}

function printWindow() {
  try {
    var opts = {
      toolbar: false,
      resizable: false,
      scrollbars: true,
      height: 640,
      width: 800
    };

    var url = 'print';
    slaveWindow = window.open(url, 'showoff_print', opts);
    slaveWindow.focus();
  }
  catch(e) {
    console.log('Failed to open print window. ' + e.message);
  }
}

function downloadWindow() {
  try {
    var opts = {
      toolbar: false,
      resizable: false,
      scrollbars: true,
      height: 640,
      width: 800
    };

    var url = 'download';
    slaveWindow = window.open(url, 'showoff_download', opts);
    slaveWindow.focus();
  }
  catch(e) {
    console.log('Failed to open download window. ' + e.message);
  }
}

function onPopState(event) {
  if (event.state && event.state.slide) {
    gotoSlide(event.state.slide-1);
  }
}

function keyDown(event){
  var key = event.keyCode;

  if (event.ctrlKey || event.metaKey) {
    // Don't interfere with browser shortcuts
    return;
  }

  debug('keyDown: ' + key);
  // avoid overriding browser commands
  if ($.inArray(key, [
      74,  // j
      75,  // k
      85,  // u
      78,  // n
      80  // p
      ]) != -1) {
    event.preventDefault();
  }
}

function keyUp(event) {
  var key = event.keyCode;

  if (event.ctrlKey || event.metaKey) {
    // Don't interfere with browser shortcuts
    return;
  }

  debug('keyUp: ' + key);
  // avoid overriding browser commands
  if ($.inArray(key, [
      74,  // j
      75,  // k
      85,  // u
      78,  // n
      80  // p
      ]) != -1) {
    event.preventDefault();
  }

  if(typeof(keymap) != 'undefined') {
    var mapping = keymap[key];
    if(mapping) {
      mapping();
    }
  }
}

function followAnchor() {
  gotoSlide(slidenum);
  debug('followAnchor: ' + slidenum);
}

function getUrlParameter(name) {
  name = name.replace(/[\[]/, '\\[').replace(/[\]]/, '\\]');
  var regex = new RegExp('[\\?&]' + name + '=([^&#]*)');
  var results = regex.exec(location.search);
  return results === null ? '' : decodeURIComponent(results[1].replace(/\+/g, ' '));
};

function connectControlChannel(url) {
  ws = new WebSocket(url);
  ws.onopen    = function()  { connected();          };
  ws.onclose   = function()  { disconnected();       }
  ws.onmessage = function(m) { parseMessage(m.data); };
}

function connected() {
  console.log('Control connection opened');
  $("#feedbackSidebar").removeClass('error');
  $("#feedbackSidebar").addClass('success');
  $("img#disconnected").hide();
  $("img#connected").show();

  try {
    // If we are a presenter, then remind the server who we are
    register();
  }
  catch (e) {
    console.log("Showoff.js was not loaded as a presenter");
  }

  sendConfig();
}

function disconnected() {
  console.log('Control connection closed');
  $("#feedbackSidebar").removeClass('success');
  $("#feedbackSidebar").addClass('error');
  $("img#connected").hide();
  $("img#disconnected").show();

  setTimeout(function() { connectControlChannel(socketUrl) } , 5000);
}

function parseMessage(data) {
  var command = JSON.parse(data);

  if ("id" in command) {
    var guid = command['id'];
    if (guid in ShowoffTracker) {
      var timer = ShowoffTracker[guid];
      clearTimeout(timer);
      delete ShowoffTracker[guid];
    }
  }

  if ("message" in command) {
    // broadcast message that was received
    try {
      var type = command['type'];
      var content = command['message'];

      switch(type) {
        case 'pace':
          paceMarker.fadeIn();
          break;

        case 'autopace':
          paceMarker.fadeIn();
          setTimeout(function() { paceMarker.fadeOut() }, 1000);
          break;

        case 'follow':
          $("#feedbackSidebar").addClass('success');
          break;

        case 'update':
          break;

        case 'navigation':
          gotoSlide(content);
          break;

        case 'position':
          var coords = content.split(',');
          $(".zoomline").zoomline('setPosition', coords[0], coords[1]);
          break;

        case 'annotations':
          break;

        case 'form':
          console.log("Received form update: " + content);
          updateForm(content);
          break;

        case 'feedback':
          console.log("Received feedback update: " + content);
          updateFeedback(content);
          break;

        case 'notes':
          var notes = content.split(/:/).pop();
          break;

        case 'chat':
          break;

        case 'poll':
          handlePollMessage(content);
          break;

        case 'activity':
          break;

        case 'response':
          break;

        default:
          console.log("Unknown message type: " + type);
      }
    }
    catch(e) {
      console.log("Unhandled error: " + e);
    }
  }

}

function sendConfig() {
  // Send information about this presentation to the server
  ws.send(JSON.stringify({
    message: 'register',
    type: 'configure',
    id: "1234",
    room: typeof(room) === "undefined" ? 'default' : room
  }));
}

function sendPing(guid) {
  // Send a ping
  ws.send(JSON.stringify({
    message: 'ping',
    type: 'ping',
    id: guid
  }));
}

function sendPong(guid) {
  // Send a pong
  ws.send(JSON.stringify({
    message: 'pong',
    type: 'pong',
    id: guid
  }));
}

function handlePollMessage(message) {
  var poll = null;
  try {
    poll = JSON.parse(message);
  }
  catch(e) {
    console.log("Invalid poll message: " + message);
    return;
  }

  if (poll.state === 'closed') {
    $(".poll[data-id=" + poll.id + "]").hide();
  }
  else {
    $(".poll[data-id=" + poll.id + "]").show();
  }
}

function updateForm(message) {
  var form = null;
  try {
    form = JSON.parse(message);
  }
  catch(e) {
    console.log("Invalid form message: " + message);
    return;
  }

  if (form.type === 'closed') {
    $(".form[data-id=" + form.id + "]").hide();
  }
  else {
    $(".form[data-id=" + form.id + "]").show();
  }
}

function updateFeedback(message) {
  var feedback = null;
  try {
    feedback = JSON.parse(message);
  }
  catch(e) {
    console.log("Invalid feedback message: " + message);
    return;
  }

  if (feedback.type === 'activity') {
    var clean = feedback.id.replace(/[^a-zA-Z0-9]/g, '');
    var element = $("#activity-" + clean);
    if (element.length > 0) {
      element.text(feedback.count);
    }
  }
}

function track(guid) {
  ShowoffTracker[guid] = setTimeout(function() { tick(guid) }, 1000);
}

function tick(guid) {
  ws.send(JSON.stringify({
    message: 'ping',
    type: 'ping',
    id: guid
  }));
}

function submitForm(form) {
  var elements = form.elements;
  var formData = {};

  // Process all submittable elements
  for (var i = 0; i < elements.length; i++) {
    var element = elements[i];
    if (element.hasAttribute('name')) {
      formData[element.name] = element.value;
    }
  }

  // Add the ID
  formData['id'] = form.dataset.id;

  // Send the data to the server
  ws.send(JSON.stringify({
    message: JSON.stringify(formData),
    type: 'form',
    id: "1234"
  }));

  return false;
}

function submitFeedback(id) {
  // Send the data to the server
  ws.send(JSON.stringify({
    message: JSON.stringify({
      id: id,
      timestamp: Date.now()
    }),
    type: 'feedback',
    id: "1234"
  }));

  return false;
}

function submitPoll(form) {
  var elements = form.elements;
  var formData = {};

  // Process all submittable elements
  for (var i = 0; i < elements.length; i++) {
    var element = elements[i];
    if (element.name === 'choice' && element.checked) {
      formData[element.name] = element.value;
    }
  }

  // Add the ID
  formData['id'] = form.dataset.id;

  // Send the data to the server
  ws.send(JSON.stringify({
    message: JSON.stringify(formData),
    type: 'poll',
    id: "1234"
  }));

  return false;
}

function expandContent() {
  $('#slides .slide .content').addClass('expanded');
}

function unexpandContent() {
  $('#slides .slide .content').removeClass('expanded');
}

function toggleContent() {
  $('#slides .slide .content').toggleClass('expanded');
}

function toggleHelp() {
  $('#help').toggle();
}

function toggleFooter() {
  $('#footer').toggle();
}

function toggleSlideNotes() {
  $('#notes').toggle();
}

function togglePresenterView() {
  $('#presenter-view').toggle();
}

function togglePrivateNotes() {
  $('#private-notes').toggle();
}

function toggleStyle() {
  $('link[rel="stylesheet"]').map(function() {
    var href = $(this).attr('href');
    var re = new RegExp("styles/([^\/]+)\.css");
    var arr = re.exec(href);
    if(arr && arr.length > 1) {
      var style = arr[1];
      var newStyle;
      if(style == 'primary') {
        newStyle = 'secondary';
      }
      else {
        newStyle = 'primary';
      }
      $(this).attr('href', 'styles/'+newStyle+'.css');
    }
  });
}

function translation(lang) {
  this.language = lang;
  this.t = function(key) {
    var keys = key.split('.');
    var obj = user_translations[this.language];
    if(obj) {
      for(var i=0; i < keys.length; i++) {
        obj = obj[keys[i]];
        if(!obj) {
          return key;
        }
      }
      return obj;
    }
    return key;
  };
}