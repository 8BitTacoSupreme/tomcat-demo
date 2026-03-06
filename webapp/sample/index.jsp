<%@ page contentType="text/html;charset=UTF-8" %>
<%@ page import="java.time.LocalDateTime, java.time.format.DateTimeFormatter" %>
<%
  String tomcatVersion = application.getServerInfo();
  String jdkVersion = System.getProperty("java.version");
  String jdkVendor = System.getProperty("java.vendor");
  String osName = System.getProperty("os.name");
  String osArch = System.getProperty("os.arch");

  // ── EDIT THIS MESSAGE FOR LIVE DEMO BUILDS ──
  String demoMessage = "Hello from Flox! Immutable packages, zero drift.";

  // Current date/time
  String dateTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

  // Determine major Tomcat version for color coding
  boolean isTomcat11 = tomcatVersion != null && tomcatVersion.contains("11.");
  String accentColor = isTomcat11 ? "#2ecc71" : "#e67e22";
  String label = isTomcat11 ? "UPGRADED" : "LEGACY";

  // Nix store path
  String storePath = System.getenv("FLOX_MANIFEST_BUILD_OUT");
  if (storePath == null || storePath.isEmpty()) {
    storePath = "/nix/store/...";
  }
%>
<!DOCTYPE html>
<html>
<head>
  <title>Flox Tomcat Demo</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #1a1a2e;
      color: #e0e0e0;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .card {
      background: #16213e;
      border: 1px solid #0f3460;
      border-radius: 12px;
      padding: 40px 48px;
      max-width: 540px;
      width: 100%;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
    }
    .badge {
      display: inline-block;
      background: <%= accentColor %>;
      color: #1a1a2e;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 1.5px;
      padding: 4px 12px;
      border-radius: 4px;
      margin-bottom: 16px;
    }
    h1 {
      font-size: 22px;
      color: #fff;
      margin-bottom: 8px;
    }
    .message {
      font-size: 15px;
      color: #aab;
      margin-bottom: 24px;
      font-style: italic;
    }
    .row {
      display: flex;
      justify-content: space-between;
      padding: 12px 0;
      border-bottom: 1px solid #0f3460;
    }
    .row:last-child { border-bottom: none; }
    .label { color: #8899aa; font-size: 14px; }
    .value {
      color: <%= accentColor %>;
      font-weight: 600;
      font-size: 14px;
      font-family: 'SF Mono', 'Fira Code', monospace;
    }
    .footer {
      margin-top: 24px;
      text-align: center;
      color: #556;
      font-size: 12px;
    }
  </style>
</head>
<body>
  <div class="card">
    <span class="badge"><%= label %></span>
    <h1>Flox Environment &mdash; Live</h1>
    <div class="message"><%= demoMessage %></div>
    <div class="row">
      <span class="label">Date / Time</span>
      <span class="value"><%= dateTime %></span>
    </div>
    <div class="row">
      <span class="label">Tomcat</span>
      <span class="value"><%= tomcatVersion %></span>
    </div>
    <div class="row">
      <span class="label">JDK</span>
      <span class="value"><%= jdkVersion %> (<%= jdkVendor %>)</span>
    </div>
    <div class="row">
      <span class="label">Platform</span>
      <span class="value"><%= osName %> / <%= osArch %></span>
    </div>
    <div class="row">
      <span class="label">Source</span>
      <span class="value"><%= storePath %></span>
    </div>
    <div class="footer">
      Served from a Flox-managed environment &mdash; zero host dependencies
    </div>
  </div>
</body>
</html>
