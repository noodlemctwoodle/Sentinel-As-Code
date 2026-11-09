metadata title = 'SendEmailReport'
metadata description = 'Sentinel incident-trigger playbook for SendEmailReport.'
metadata lastUpdateTime = '24-03-2026'
metadata entities = []
metadata tags = [
  'Incident'
  'Source: Sentinel-As-Code'
]
metadata support = {
  tier: 'community'
}
metadata author = {
  name: 'noodlemctwoodle'
}

@description('The Logic App\'s name.')
param PlaybookName string = 'SendEmailReport'

@description('The playbook resource group; the deploy fills it in.')
param AutomationResourceGroup string = ''

@description('The Sentinel workspace\'s name; the deploy fills it in.')
param SentinelWorkpaceName string = ''

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var microsoftSentinelConnectionName = 'MicrosoftSentinel-${PlaybookName}'
var office365ConnectionName = 'Office365-${PlaybookName}'

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: PlaybookName
  location: location
  tags: {
    Source: 'Sentinel-As-Code'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        reportName: {
          defaultValue: 'Sentinel Security Ops'
          type: 'String'
        }
        SecOpsEmail: {
          defaultValue: 'secops@yourdomain.com'
          type: 'String'
        }
        emailLogoHeader: {
          defaultValue: 'https://domain.com/content/images/2025/04/36127.png'
          type: 'String'
        }
        dateTimeFormat: {
          defaultValue: 'dd-MM-yyyy HH:mm:ss'
          type: 'String'
        }
        Recipient: {
          defaultValue: 'socengineer@domain.com'
          type: 'String'
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Microsoft_Sentinel_incident: {
          type: 'ApiConnectionWebhook'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuresentinel\'][\'connectionId\']'
              }
            }
            body: {
              callback_url: '@{listCallbackUrl()}'
            }
            path: '/incident-creation'
          }
        }
      }
      actions: {
        Create_HTML_table_with_Alerts: {
          runAfter: {
            Select_Alerts: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Select_Alerts\')'
            format: 'HTML'
          }
        }
        Create_HTML_table_with_Entities: {
          runAfter: {
            Select_Entities: [
              'Succeeded'
            ]
          }
          type: 'Table'
          inputs: {
            from: '@body(\'Select_Entities\')'
            format: 'HTML'
          }
        }
        Select_Alerts: {
          runAfter: {
            Create_HTML_table_with_Entities: [
              'Succeeded'
            ]
          }
          type: 'Select'
          inputs: {
            from: '@triggerBody()?[\'object\']?[\'properties\']?[\'Alerts\']'
            select: {
              Alerts: '@{item()?[\'properties\']?[\'alertDisplayName\']}'
            }
          }
        }
        Select_Entities: {
          runAfter: {}
          type: 'Select'
          inputs: {
            from: '@triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\']'
            select: {
              Entity: '@{item()?[\'properties\']?[\'friendlyName\']}'
              'Entity type': '@{item()?[\'kind\']}'
            }
          }
        }
        Send_an_email_with_Incident_details: {
          runAfter: {
            Compose_Email_response: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365-1\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              To: '@parameters(\'Recipient\')'
              Subject: 'New Microsoft Sentinel incident - @{triggerBody()?[\'object\']?[\'properties\']?[\'title\']}'
              Body: '<p>@{outputs(\'Compose_Email_response\')}</p>'
              Importance: 'High'
            }
            path: '/v2/Mail'
          }
        }
        Compose_Entity_Count: {
          runAfter: {
            Create_HTML_table_with_Alerts: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '@length(triggerBody()?[\'object\']?[\'properties\']?[\'relatedEntities\'])'
        }
        Compose_Email_response: {
          runAfter: {
            Compose_Entity_Count: [
              'Succeeded'
            ]
          }
          type: 'Compose'
          inputs: '''
<!DOCTYPE html>
<html>

<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Alert</title>
    <style>
        /* Basic page styling */
        body {
            font-family: 'Segoe UI', Arial, sans-serif; /* Microsoft's Segoe UI for better visual alignment */
            margin: 0; 
            padding: 0; 
            background-color: #f5f5f5; /* Light gray background for better contrast */
            color: #252525; /* Darker text for better readability */
            line-height: 1.5; /* Better line spacing for readability */
        }

        /* Main container with max width and centered */
        .container { 
            max-width: 700px; /* Slightly wider container */
            margin: 20px auto; /* Add top/bottom margin */
            background-color: #ffffff; /* White background for content */
            box-shadow: 0 2px 10px rgba(0,0,0,0.1); /* Enhanced shadow for depth */
            border-radius: 4px; /* Subtle rounded corners for modern look */
            overflow: hidden; /* Ensure no content spills out */
        }

        /* Header styling with logo on right, title on left */
        .header {
            background-color: #0078D4; /* Microsoft blue background */
            padding: 24px 20px; /* Increased vertical padding */
            color: white; /* White text for contrast on blue */
            display: flex; /* Use flexbox for layout */
            justify-content: space-between; /* Push elements to opposite ends */
            align-items: center; /* Vertically center elements */
            min-height: 80px; /* Ensure header has enough height */
        }

        /* Logo styling - positioned on the right */
        .header img { 
            width: 120px !important; /* Force the width with !important to override email client defaults */
            height: auto !important; /* Maintain aspect ratio */
            max-width: none !important; /* Override any max-width constraints */
            object-fit: contain; /* Ensure image isn't distorted */
            margin: 0;
            order: 2; /* Places the image second in the flex order (right side) */
        }

        /* Title styling - positioned on the left */
        .header h1 {
            margin: 0;
            font-size: 28px; /* Larger font size */
            text-align: left;
            order: 1; /* Places the title first in the flex order (left side) */
            font-weight: 600; /* Slightly bolder */
            letter-spacing: 0.5px; /* Subtle letter spacing for better legibility */
        }

        /* Main content area */
        .content {
            padding: 24px; /* Consistent padding */
            background-color: #ffffff;
        }

        /* Report name banner styling - displayed below header */
        .report-name-banner {
            background-color: #f0f7ff;
            padding: 12px 16px;
            margin-bottom: 20px;
            font-weight: 600;
            font-size: 16px;
            color: #0078D4;
            border-left: 4px solid #0078D4;
            border-radius: 0 4px 4px 0; /* Rounded on right side only */
        }

        /* Title section containing alert title and severity */
        .title-section {
            margin: 0 0 24px 0;
        }

        /* Alert header containing title and severity */
        .alert-header {
            margin: 20px 0;
            display: flex;
            justify-content: center;
            align-items: center;
            flex-direction: column;
        }

        /* Title wrapper to contain both title and badge */
        .alert-title-wrapper {
            display: flex;
            align-items: center;
            justify-content: center;
            flex-wrap: wrap;
            gap: 12px;
            margin-bottom: 8px;
        }

        .alert-container {
            background-color: #f0f7ff;
            border-left: 4px solid #0078D4;
            border-radius: 0 4px 4px 0;
            padding: 16px 20px;
            margin: 20px 0;
            display: flex;
            flex-direction: column;
            width: 100%;
            box-sizing: border-box;
            position: relative; /* For absolute positioning of severity */
        }

        .alert-row {
            display: flex;
            align-items: center;
            justify-content: space-between; /* Push title and severity to opposite ends */
            width: 100%;
        }

        .alert-title {
            color: #333 !important; /* Force color override */
            font-size: 18px !important;
            font-weight: 600 !important;
            margin: 0 !important;
            padding-right: 100px; /* Make room for severity indicator */
            flex-grow: 1;
        }

        .severity-indicator {
            background-color: #dbc522; /* Yellow for low severity */
            color: white !important;
            padding: 5px 12px;
            border-radius: 30px;
            font-weight: 600;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            display: inline-block;
            position: absolute; /* Position absolutely */
            right: 20px; /* Position on the right */
            top: 50%; /* Center vertically */
            transform: translateY(-50%); /* Perfect vertical centering */
        }

        /* Override for other severity colors */
        .severity-high {
            background-color: #D13438 !important;
        }

        .severity-medium {
            background-color: #FF8C00 !important;
        }

        .severity-low {
            background-color: #dbc522 !important;
        }

        .severity-informational {
            background-color: #767676 !important;
        }

        /* Executive summary section styling */
        .summary {
            background-color: #f9f9f9; /* Light gray background */
            border-left: 4px solid #0078D4; /* Blue left border for visual interest */
            padding: 16px;
            margin: 0 0 24px 0;
            border-radius: 0 4px 4px 0; /* Rounded on right side only */
            box-shadow: 0 1px 3px rgba(0,0,0,0.05); /* Very subtle shadow */
        }

        /* Basic information row styling */
        .info-row {
            margin-bottom: 16px;
            display: flex;
            flex-wrap: wrap;
        }

        /* Label styling for info pairs */
        .info-label {
            font-weight: 600;
            width: 130px;
            display: inline-block;
            vertical-align: top;
            color: #444;
        }

        /* Metrics section with improved mobile responsiveness */
        .metrics {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin: 15px 0 25px 0;
        }

        /* Individual metric card styling */
        .metric-card {
            flex: 1;
            min-width: 120px;
            background-color: #f9f9f9; /* Light gray background */
            padding: 15px;
            border-radius: 4px;
            text-align: center;
            border: 1px solid #eee; /* Light border */
        }

        /* Metric value (number) styling */
        .metric-value {
            font-size: 20px;
            font-weight: bold;
            color: #0078D4; /* Microsoft blue */
            margin-bottom: 5px;
        }

        /* Metric label styling */
        .metric-label {
            font-size: 12px;
            color: #666; /* Medium gray */
        }

        /* Link styling */
        .link {
            color: #0078D4; /* Microsoft blue for links */
            text-decoration: none;
            transition: color 0.2s ease; /* Smooth color transition */
        }

        .link:hover {
            color: #005a9e; /* Darker blue on hover */
            text-decoration: underline;
        }

        /* Timeline visualization styling */
        .timeline {
            margin: 28px 0;
            position: relative;
            border-left: 4px solid #0078D4; /* Increased from 3px to 4px to match other sections */
            padding-left: 24px;
        }

        .timeline-item {
            position: relative;
            margin-bottom: 20px;
        }

        /* Timeline dots for each event - adjusted positioning for the thicker line */
        .timeline-item:before {
            content: '';
            position: absolute;
            left: -34px; /* Adjusted for the thicker line */
            top: 0;
            width: 18px;
            height: 18px;
            border-radius: 50%; /* Create circular dots */
            background-color: #0078D4;
            border: 4px solid white; /* White border around dots */
            box-shadow: 0 0 0 1px rgba(0,120,212,0.2); /* Subtle outline */
        }

        /* Timeline date styling */
        .timeline-date {
            color: #555;
            font-size: 14px;
            margin-bottom: 4px;
            font-weight: 500;
        }

        /* Timeline event title */
        .timeline-title {
            font-weight: 600;
            margin-bottom: 5px;
            color: #333;
            font-size: 16px;
        }

        /* MITRE ATT&CK Tactics section */
        .tactics {
            background-color: #f9f9f9;
            border-left: 4px solid #0078D4; /* Blue left border */
            padding: 16px;
            margin: 24px 0;
            border-radius: 0 4px 4px 0; /* Rounded on right side only */
            box-shadow: 0 1px 3px rgba(0,0,0,0.05); /* Very subtle shadow */
        }

        .tactics ul {
            margin: 12px 0 0 0;
            padding-left: 20px;
        }

        .tactics li {
            margin-bottom: 8px;
        }

        /* Recommended actions section */
        .recommendations {
            background-color: #f0f7ff; /* Light blue background */
            padding: 18px;
            margin: 24px 0;
            border-left: 4px solid #0078D4; /* Blue left border */
            border-radius: 0 4px 4px 0; /* Rounded on right side only */
            box-shadow: 0 1px 3px rgba(0,0,0,0.05); /* Very subtle shadow */
        }

        .recommendations ul {
            margin: 12px 0 0 0;
            padding-left: 20px;
        }

        .recommendations li {
            margin-bottom: 10px;
            position: relative;
        }

        /* Action buttons container */
        .action-buttons {
            text-align: center;
            margin: 30px 0;
        }

        /* Button styling */
        .button {
            padding: 14px 24px;
            background-color: #0078D4; /* Microsoft blue */
            color: white !important; /* Force white color with !important */
            text-decoration: none;
            border-radius: 4px;
            font-weight: 600;
            font-size: 15px;
            text-align: center;
            border: none;
            cursor: pointer;
            display: inline-block;
            min-width: 180px; /* Ensure minimum width */
            height: auto !important; /* Prevent height overrides */
            line-height: 1.5 !important; /* Ensure proper line height */
            box-shadow: 0 2px 5px rgba(0,0,0,0.1); /* Add shadow for depth */
            transition: all 0.2s ease; /* Smooth transition for hover effect */
            -webkit-text-size-adjust: none; /* Prevent iOS text size adjustment */
            -ms-text-size-adjust: none; /* Prevent Windows text size adjustment */
        }

        .button:hover {
            background-color: #005a9e; /* Darker blue on hover */
            box-shadow: 0 4px 8px rgba(0,0,0,0.15); /* Enhanced shadow on hover */
            transform: translateY(-2px); /* Slight rise effect */
        }

        .button span {
            color: white !important;
            display: inline-block !important;
            width: auto !important;
            visibility: visible !important;
        }

        /* Section styling for main content divisions */
        .section {
            margin: 30px 0;
            border-top: 1px solid #eee; /* Light top border */
            padding-top: 20px;
        }

        /* Section title styling with indicator */
        .section-title {
            font-size: 18px;
            margin-bottom: 15px;
            color: #333;
            font-weight: 600;
            display: flex;
            align-items: center;
        }

        /* Colored dot before section titles */
        .section-title-indicator {
            width: 12px;
            height: 12px;
            border-radius: 50%; /* Create circular indicator */
            background-color: #0078D4;
            display: inline-block;
            margin-right: 10px;
        }

        /* IP location text styling */
        .ip-location {
            font-size: 12px;
            color: #666;
            margin-top: 4px;
        }

        /* Footer styling */
        .footer {
            padding: 24px;
            background-color: #f0f0f0; /* Light gray background */
            text-align: center;
            border-top: 1px solid #ddd; /* Light top border */
        }

        .footer h3 {
            margin-top: 0;
            color: #333;
        }

        /* Table styling for Sentinel tables - minimal to avoid conflicts but improved */
        .sentinel-tables table {
            width: 100%;
            margin-bottom: 24px;
            border-collapse: collapse;
            box-shadow: 0 1px 3px rgba(0,0,0,0.05); /* Subtle shadow */
            border-radius: 4px; /* Rounded corners */
            overflow: hidden; /* Ensure rounded corners work with table */
        }

        .sentinel-tables th {
            background-color: #0078D4; /* Microsoft blue headers */
            color: white;
            text-align: left;
            padding: 12px 15px;
            font-weight: 500;
            font-size: 14px;
        }

        .sentinel-tables tr:nth-child(even) {
            background-color: #f5f5f5; /* Striped rows for readability */
        }

        .sentinel-tables tr:hover {
            background-color: #f0f7ff; /* Highlight row on hover */
        }

        .sentinel-tables td {
            padding: 12px 15px;
            border-bottom: 1px solid #eee; /* Light borders between rows */
            font-size: 14px;
        }

        /* Print-specific styling for better readability when printed */
        @media print {
            body {
                background-color: white;
                color: black;
            }
            
            .container {
                max-width: 100%;
                box-shadow: none;
            }
            
            .button {
                border: 1px solid #333;
                color: black;
                background: none;
            }
            
            a {
                color: black;
                text-decoration: underline;
            }
            
            .header {
                background-color: #f0f0f0;
                color: black;
            }
        }

        /* Mobile responsive adjustments */
        @media (max-width: 600px) {
            .header {
                flex-direction: column;
                text-align: center;
                padding: 16px;
            }
            
            .header h1 {
                order: 1;
                margin-bottom: 12px;
            }
            
            .header img {
                order: 2;
            }
            
            .info-label {
                display: block;
                width: 100%;
                margin-bottom: 4px;
            }
            
            .action-buttons {
                flex-direction: column;
            }
            
            /* Improved metrics styling for mobile */
            .metrics {
                display: flex;
                flex-direction: row; /* Force horizontal layout even on mobile */
                justify-content: space-between;
                flex-wrap: nowrap; /* Prevent wrapping to maintain horizontal alignment */
            }
            
            .metric-card {
                min-width: 0; /* Allow cards to shrink */
                flex-basis: 32%; /* Set approximate width for 3 cards */
                margin: 0; /* Remove any margin that might cause wrapping */
            }
            
            .metric-value {
                font-size: 18px; /* Slightly smaller font for mobile */
            }
            
            .metric-label {
                font-size: 10px; /* Smaller label text for mobile */
            }
            
            /* Fix alert container on mobile */
            .alert-container {
                padding: 12px 15px; /* Reduce padding slightly */
            }
            
            .alert-row {
                flex-direction: column;
                align-items: flex-start;
            }
            
            .alert-title {
                padding-right: 0;
                margin-bottom: 10px !important;
                font-size: 16px !important; /* Smaller font size on mobile */
            }
            
            .severity-indicator {
                position: static;
                transform: none;
                margin-top: 8px;
                align-self: flex-start; /* Align to the left */
            }
            
            /* Timeline adjustments for mobile */
            .timeline {
                padding-left: 18px;
            }
            
            .timeline-item:before {
                left: -27px;
                width: 14px;
                height: 14px;
            }
        }
    </style>
</head>

<body>
    <div class="container">
        <!-- Header with SECURITY ALERT title on left and logo on right -->
        <div class="header">
            <h1>SECURITY ALERT</h1>
            <img src="@{parameters('emailLogoHeader')}" alt="Company Logo">
        </div>
        
        <div class="content">
            <!-- Report name banner below header -->
            <div class="report-name-banner">
                @{parameters('reportName')}
            </div>
            
            <!-- Date time at top right -->
            <div class="incident-date">
                <strong>Date & Time:</strong>
                @{formatDateTime(triggerBody()?['object']?['properties']?['createdTimeUtc'],
                parameters('dateTimeFormat'))}
            </div>

            <!-- New alert header container with fixed positioning -->
            <div class="alert-container">
                <div class="alert-row">
                    <!-- Title with forced styling -->
                    <h2 class="alert-title">
                        @{triggerBody()?['object']?['properties']?['title']}
                    </h2>
                    
                    <!-- Severity with absolute positioning -->
                    <span class="severity-indicator severity-@{toLower(triggerBody()?['object']?['properties']?['severity'])}">
                        @{triggerBody()?['object']?['properties']?['severity']}
                    </span>
                </div>
            </div>
        
            <!-- Executive Summary -->
            <div class="summary">
                <strong>Executive Summary:</strong> Security alert triggered for
                @{if(equals(coalesce(triggerBody()?['object']?['properties']?['additionalData']?['tactics'], ''), ''),
                'suspicious activity',
                concat(first(triggerBody()?['object']?['properties']?['additionalData']?['tactics']), ' activity'))}
                involving multiple entities.
                Immediate investigation recommended.
            </div>


            <!-- Metrics section with improved mobile responsiveness -->
            <div class="metrics">
                <div class="metric-card">
                    <div class="metric-value">
                        @{coalesce(triggerBody()?['object']?['properties']?['additionalData']?['alertsCount'], '1')}
                    </div>
                    <div class="metric-label">Alerts</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">
                        @{outputs('Compose_Entity_Count')}
                    </div>
                    <div class="metric-label">Entities</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value">
                        @{coalesce(triggerBody()?['object']?['properties']?['severity'], 'Med')}
                    </div>
                    <div class="metric-label">Severity</div>
                </div>
            </div>

            <!-- Basic info -->
            <div class="info-row">
                <span class="info-label">Incident ID:</span>
                <span>@{coalesce(triggerBody()?['object']?['properties']?['incidentNumber'], 'N/A')}</span>
            </div>

            <div class="info-row">
                <span class="info-label">Description:</span>
                <span>@{triggerBody()?['object']?['properties']?['description']}
@{triggerBody()?['object']?['properties']?['additionalData']?['alertProductNames']}</span>
            </div>

            <!-- Visual Timeline -->
            <div class="timeline">
                <div class="timeline-item">
                    <div class="timeline-date">
                        @{if(equals(coalesce(triggerBody()?['object']?['properties']?['firstActivityTimeUtc'], ''), ''),
                        formatDateTime(triggerBody()?['object']?['properties']?['createdTimeUtc'],
                        parameters('dateTimeFormat')),
                        formatDateTime(triggerBody()?['object']?['properties']?['firstActivityTimeUtc'],
                        parameters('dateTimeFormat')))}
                    </div>
                    <div class="timeline-title">First Activity Detected</div>
                    <div>Initial suspicious activity observed</div>
                </div>
                <div class="timeline-item">
                    <div class="timeline-date">
                        @{formatDateTime(triggerBody()?['object']?['properties']?['createdTimeUtc'],
                        parameters('dateTimeFormat'))}
                    </div>
                    <div class="timeline-title">Incident Created</div>
                    <div>Alert generated by Microsoft Sentinel</div>
                </div>
                <div class="timeline-item">
                    <div class="timeline-date">Now</div>
                    <div class="timeline-title">Notification Sent</div>
                    <div>Security team notified</div>
                </div>
            </div>

            <!-- Tactics Section -->
            <div class="tactics">
                <div class="section-title">
                    <span class="section-title-indicator"></span>
                    MITRE ATT&CK Tactics
                </div>
                <ul>
                    @{if(equals(coalesce(triggerBody()?['object']?['properties']?['additionalData']?['tactics'], ''),
                    ''),
                    '<li>No tactics identified</li>',
                    join(triggerBody()?['object']?['properties']?['additionalData']?['tactics'], '<br>'))}
                </ul>
            </div>

            <!-- Recommended actions section - Made more specific -->
            <div class="recommendations">
                <div class="section-title">
                    <span class="section-title-indicator"></span>
                    Recommended Actions
                </div>
                <ul>
                    <li>Investigate the affected resources and validate the alert</li>
                    <li>Check for unusual authentication patterns or access attempts</li>
                    <li>Review related logs in Microsoft Sentinel for additional context</li>
                </ul>
            </div>

            <!-- Single action button with improved mobile compatibility -->
            <div class="action-buttons">
                <a class="button" href="@{triggerBody()?['object']?['properties']?['incidentUrl']}">
                    <span>Investigate Incident</span>
                </a>
            </div>

            <!-- Entities Section - With tag directly -->
            <div class="section">
                <div class="section-title">
                    <span class="section-title-indicator"></span>
                    Affected Entities
                </div>
                <!-- Remove custom table styling and let Sentinel's table render as is -->
                <div class="sentinel-tables">
                    @{body('Create_HTML_table_with_Entities')}
                </div>
            </div>

            <!-- Alerts Section - Modified to avoid styling conflicts -->
            <div class="section">
                <div class="section-title">
                    <span class="section-title-indicator"></span>
                    Related Alerts
                </div>
                <!-- Remove custom table styling and let Sentinel's table render as is -->
                <div class="sentinel-tables">
                    @{body('Create_HTML_table_with_Alerts')}
                </div>
            </div>
        </div>

        <div class="footer">
            <h3>Sentinel Security Team</h3>
            <p>If you have any questions, please contact us:</p>
            <p><a class="link" href="mailto:@{parameters('SecOpsEmail')}">@{parameters('SecOpsEmail')}</a></p>
            <p style="margin-top: 15px; font-size: 12px; color: #999;">This is an automated security alert.</p>
        </div>
    </div>
</body>

</html>'''
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuresentinel: {
            connectionId: microsoftSentinelConnection.id
            connectionName: microsoftSentinelConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
          'office365-1': {
            connectionId: office365Connection.id
            connectionName: office365ConnectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
    }
  }
}

resource microsoftSentinelConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: microsoftSentinelConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: microsoftSentinelConnectionName
    customParameterValues: {}
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azuresentinel')
    }
  }
}

resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: office365ConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: office365ConnectionName
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
  }
}
