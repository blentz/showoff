/**
 * Centralized Mermaid configuration for Showoff
 * Handles initialization for presentation, print, and custom themes
 */
(function() {
  'use strict';

  // Prevent multiple initializations
  if (window.ShowoffMermaidConfigured) {
    return;
  }

  /**
   * Initialize mermaid with appropriate theme based on context
   * @param {Object} customTheme - Optional custom theme override (e.g., from presentation theme)
   */
  window.initShowoffMermaid = function(customTheme) {
    if (!window.mermaid) {
      console.warn('[MERMAID] Mermaid library not loaded');
      return;
    }

    var isOnepageMode = document.body.classList.contains('onepage');
    var ganttWidth = 900;

    // Default print-friendly theme for onepage/print modes
    var printTheme = {
      primaryColor: '#e3f2fd',
      primaryTextColor: '#000',
      primaryBorderColor: '#1976d2',
      lineColor: '#333',
      secondaryColor: '#fff3e0',
      tertiaryColor: '#f3e5f5',
      mainBkg: '#ffffff',
      textColor: '#000000',
      labelTextColor: '#000000',
      // Pie chart colors - diverse, print-friendly palette
      pie1: '#4caf50',  // Green
      pie2: '#2196f3',  // Blue
      pie3: '#ff9800',  // Orange
      pie4: '#9c27b0',  // Purple
      pie5: '#f44336',  // Red
      pie6: '#00bcd4',  // Cyan
      pie7: '#ffeb3b',  // Yellow
      pie8: '#795548',  // Brown
      pie9: '#607d8b',  // Blue Grey
      pie10: '#e91e63', // Pink
      pie11: '#8bc34a', // Light Green
      pie12: '#ffc107', // Amber
      pieTitleTextSize: '20px',
      pieTitleTextColor: '#000000',
      pieSectionTextSize: '14px',
      pieSectionTextColor: '#000000',
      pieLegendTextSize: '14px',
      pieLegendTextColor: '#000000',
      pieStrokeColor: '#ffffff',
      pieStrokeWidth: '2px',
      pieOpacity: '0.8',
      // Gantt-specific colors for print
      gridColor: '#ccc',
      sectionBkgColor: '#e3f2fd',
      altSectionBkgColor: '#fff3e0',
      sectionBkgColor2: '#f3e5f5',
      taskBorderColor: '#1976d2',
      taskBkgColor: '#bbdefb',
      taskTextColor: '#000000',
      taskTextOutsideColor: '#000000',
      taskTextClickableColor: '#000000',
      activeTaskBorderColor: '#1565c0',
      activeTaskBkgColor: '#90caf9',
      doneTaskBkgColor: '#a5d6a7',
      doneTaskBorderColor: '#388e3c',
      critBorderColor: '#d32f2f',
      critBkgColor: '#ef9a9a',
      todayLineColor: '#f44336'
    };

    // Determine which theme to use
    var themeVariables = {};
    if (isOnepageMode) {
      // Print mode: Always use print-friendly theme
      themeVariables = printTheme;
    } else if (customTheme) {
      // Presentation mode with custom theme
      themeVariables = customTheme;
    }
    // else: Presentation mode with no custom theme uses mermaid defaults

    var config = {
      startOnLoad: false,
      theme: isOnepageMode ? 'default' : (customTheme ? 'base' : 'default'),
      maxTextSize: isOnepageMode ? 50000 : 99999,
      themeVariables: themeVariables,
      gantt: {
        useWidth: ganttWidth,
        useMaxWidth: isOnepageMode ? true : false,
        barHeight: 25,
        barGap: 6,
        topPadding: isOnepageMode ? 50 : 75,
        leftPadding: isOnepageMode ? 75 : 150,
        rightPadding: 20,
        gridLineStartPadding: isOnepageMode ? 35 : 40,
        fontSize: 12,
        sectionFontSize: 14,
        titleTopMargin: isOnepageMode ? 25 : 40,
        numberSectionStyles: 4,
        displayMode: ''
      },
      flowchart: {
        useMaxWidth: true,
        htmlLabels: true
      },
      sequence: {
        useMaxWidth: true
      },
      pie: {
        useMaxWidth: true
      }
    };

    mermaid.initialize(config);

    window.ShowoffMermaidConfigured = true;
    console.log('[MERMAID] Initialized for', isOnepageMode ? 'print/onepage' : 'presentation', 'mode');
  };

  // Don't auto-initialize - let either showoff.js or presentation theme call initShowoffMermaid()
  // This ensures presentation themes can override with custom colors
})();
