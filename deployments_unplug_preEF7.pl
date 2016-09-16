#!ec-perl
# Unplug+Flot plugin content
#
# To be used in Electric Flow version prior to 7.0
#
# Description: Plot deployment history
#
# Run from the command line to debug:
#	ec-perl deployments_unplug_preEF7.pl
#
# Load content into unplug location:
# 	ectool setProperty /server/unplug/v8 --valueFile deployments_unplug_preEF7.pl
#
# Run from the URL to view in Commander
# 	https://flow/commander/pages/unplug/un_run8
#

# Revision history
#   9/15/2016 - 1.0 Initial working version
#   TODO - 1.1 Updated for CEV-11985 workaround

my $unplugIndex = 8;

my $DEBUG=0;
if (!$ENV{'GATEWAY_INTERFACE'}) {
	my $XHTML;
	$DEBUG=1;
} else {
	use strict;
}

use ElectricCommander;
use DateTime;
use Data::Dumper;

$XHTML = << 'ENDOFHEADER';
$[/server/unplug/lib/use-flot]
ENDOFHEADER

my $timeInterval = 1;   # Size of time window in days
my $maxIntervals =  20;    # Number of intervals
my $projectList = "ALL";  # Application projects, comma-separated list or ALL for all projects

$timeInterval = ($cgi->url_param('timeInterval'))?$cgi->url_param('timeInterval'):$timeInterval;
$maxIntervals = ($cgi->url_param('maxIntervals'))?$cgi->url_param('maxIntervals'):$maxIntervals;
$projectList = ($cgi->url_param('projectList'))?$cgi->url_param('projectList'):$projectList;

$XHTML .= qq(
<!--
<form action="un_run${unplugIndex}?timeInterval=${timeInterval}&maxIntervals=${maxIntervals}&projectList=${projectList}">
-->
<form action="un_run${unplugIndex}?timeInterval=${timeInterval}">
  Time interval (days):<input type="text" name="timeInterval" value="$timeInterval"/>
  Number of intervals:<input type="text" name="maxIntervals" value="$maxIntervals"/>
  Project List (comma-separated or ALL for all projects):<input type="text" name="projectList" value="$projectList"/>
  <input type="submit" value="Submit"/>
</form>
);

my %deployResult;
my %runTime;
my %colors=(
    'success' => "green",
    'error'   => "red"
    );

my $ec = new ElectricCommander({format=>'json'});

my @projects; 
if ($projectList eq "ALL") {
	my $projectsResponse = $ec->getProjects()->{responses}[0]->{project};
	for my $project (@{$projectsResponse}) {
		push (@projects, $project->{projectName}) if (!$project->{pluginName}); # skip plugins
	}
} else {
	@projects = split(",",$projectList);
}

my @deployments;

# Workaround for the API not respecting the project name (CEV-11985)
my $deploymentHistoryItems;
my $index = 0;
for my $project (@projects) {
	# Get Deployment History
	$deploymentHistoryItems = $ec->getDeploymentHistoryItems({
			#applicationName=>"",
			#environmentName=>"",
			#environmentProjectName=>"",
			#latest=>"0",
			#processName=>"",
			#snapshotName=>"",
			projectName=>$project # required field
			# Workaround for the API not respecting the project name (CEV-11985)
			})->{responses}[0]->{deploymentHistoryItem} if ($index == 0);

		$index++;
		
	foreach my $deploymentItem (@{$deploymentHistoryItems}) {
		push @deployments, {
			applicationName=>$deploymentItem->{applicationName},
			status=>$deploymentItem->{status},
			completionTime=>$deploymentItem->{completionTime},
			runTime=>$deploymentItem->{runTime}
			# Other available fields
			#propertySheetId
			#applicationProcessName
			#smartDeploy
			#deploymentHistoryItemName
			#applicationProcessId
			#owner
			#applicationId
			#jobId
			#createTime
			#headApplicationId
			#modifyTime
			#applicationProjectName
			#deploymentHistoryItemId
		# Workaround for the API not respecting the project name (CEV-11985)
		} if ($deploymentItem->{applicationProjectName} eq $project);
	}
}

#print Dumper @deployments;
		
# Loop over date intervals

for (my $i=0; $i < $maxIntervals; $i++) {
	my $startDateAgo = ($maxIntervals - $i) * $timeInterval;
	my $endDateAgo = ($maxIntervals - $i - 1) * $timeInterval;
	
	#print "startDateAgo=$startDateAgo endDateAgo=$endDateAgo ||| ";

	my $endDateBase = DateTime->now()->subtract(days => $endDateAgo);
	my $startDateBase = DateTime->now()->subtract(days => $startDateAgo);
	
	my $endDate = $endDateBase->iso8601() . ".000Z";
	my $startDate = $startDateBase->iso8601() . ".000Z";

	my $endDateEpoch = $endDateBase->epoch() * 1000;
	my $startDateEpoch = $startDateBase->epoch() * 1000;
	
	my $date = $endDate;
	$date =~ s/([\d\-]+)T.+/$1/;
	
	#print "startDate=$startDate endDate=$endDate startDateEpoch=$startDateEpoch endDateEpoch=$endDateEpoch \n";

	#print $date,"\n";
	$deployResult{$date}{'success'} = 0;
	$deployResult{$date}{'error'} = 0;
	foreach my $deployment (@deployments) {
		my $completionTime = $deployment->{completionTime};
		# If the completion time within the time slot
		if ($startDateEpoch < $completionTime && $completionTime <= $endDateEpoch) {
			my $name = $deployment->{applicationName};
			my $outcome = $deployment->{status};
			my $durationTime = $deployment->{runTime};	# duration in ms
			$deployResult{$date}{$outcome} ++;
			if ($outcome eq "success") {
				$runTime{$date} += $durationTime;
			}			
			#print "name=$name outcome=$outcome durationTime=$durationTime\n";
		}
	}
	
} 
	
#print Dumper %deployResult;
#print Dumper %runTime;

# Create Build Time Line
$XHTML .= '<script type="text/javascript">
//<![CDATA[
$(function() {
';

#
# Generate Data points for each outcome
# 
foreach my $outcome ('success', 'error') {
    # comma separated if not 1st
    $XHTML .= "var $outcome = [ ";
    my $counter=1;
    foreach my $date (sort keys %deployResult) {
        # ccomma separated if not 1st
        $XHTML .= ", " if ($counter != 1);
        $XHTML .= sprintf("[%d, %d]", $counter++, $deployResult{$date}{$outcome});
    }
    $XHTML .= " ];\n ";
}

#
# Generate Run Time Data
#
$XHTML .= 'var runTime = [';
my $counter=1;
foreach my $date (sort keys %deployResult) {
    # ccomma separated if not 1st
    $XHTML .= ", " if ($counter != 1);
    $XHTML .= sprintf("[%d, %d]", $counter++, 
                $deployResult{$date}{'success'} ==0 ? 0: $runTime{$date}/1000/$deployResult{$date}{'success'});
}
$XHTML .= " ];\n";

#
# Set options
#
$XHTML .= '    var options = {
        series: {
            bars: {
                align: "center", 
                barWidth: 0.7
            }
        },
        yaxes: [{position: "left"}, {position: "right"}],
        xaxis: {
            ticks:[ ';         
#
# Set Date as X-axis   
my $counter=1;
foreach my $date (sort keys %deployResult) {
    # comma separated if not 1st
    $XHTML .= ", " if ($counter != 1);
    $XHTML .= sprintf("[%d, \'%s\']", $counter++, $date);
}
$XHTML .= '        ]
        }
    };    
';

#
# Generate Graph itself
$XHTML .= '
/*
	var options = {
		yaxis : [{position: "right"},{position: "left"}]
	};
*/
    $.plot("#placeholder",
		[
			{data: success, label: "success", yaxis:1, bars :{ show: true, fill: 1, order: 1}, stack:true, color: "green"},
			{data: error, label: "error", yaxis:1, bars :{ show: true, fill: 1, order: 2}, stack:true, color: "red"},
			{data: runTime, label: "Deploy Time (sec)", yaxis: 2, lines: { show: true}, points: {show: true}, color: "purple"}
        ], options);
    // Add the Flot version string to the footer
    $("#footer").prepend("Flot " + $.plot.version + " &ndash; ");
});
//]]>
</script>
<div id="header">
    <h1>Deployment History</h1>
';

$XHTML .= '	
</div>
<div>
    <p>Number of deployments and average duration</p>
</div>
<div id="content">
    <div class="demo-container" style="
        box-sizing: border-box;
        width: 850px;
        height: 450px;
        padding: 20px 15px 15px 15px;
        margin: 15px auto 30px auto;
        border: 1px solid #ddd;
        background: #fff;
        background: linear-gradient(#f6f6f6 0, #fff 50px);
        background: -o-linear-gradient(#f6f6f6 0, #fff 50px);
        background: -ms-linear-gradient(#f6f6f6 0, #fff 50px);
        background: -moz-linear-gradient(#f6f6f6 0, #fff 50px);
        background: -webkit-linear-gradient(#f6f6f6 0, #fff 50px);
        box-shadow: 0 3px 10px rgba(0,0,0,0.15);
        -o-box-shadow: 0 3px 10px rgba(0,0,0,0.1);
        -ms-box-shadow: 0 3px 10px rgba(0,0,0,0.1);
        -moz-box-shadow: 0 3px 10px rgba(0,0,0,0.1);
        -webkit-box-shadow: 0 3px 10px rgba(0,0,0,0.1);">
    <div id="placeholder" class="demo-placeholder" style="width:100%;height:100%;font-size:14px;line-height:1.2em;"></div>

    </div>
</div>';

#
# Show a table as well
$XHTML .= '
<h2>Raw Data</h2>
<div>
    <p>The raw data associated with the graph above.</p>
</div>

<TABLE border="3" ><TR><TH>Date</TH><TH>success</TH><TH>error</TH>
<TH width="20">Successful Deploy Average Duration (sec)</TH></TR>';
my %total=('success'=>0,'error'=>0);
foreach my $date (sort keys %deployResult) {
  $total{'success'}  += $deployResult{$date}{'success'};
  $total{'error'}   += $deployResult{$date}{'error'};
  $XHTML .= sprintf("<TR><TD>%s</TD><TD>%d</TD><TD>%d</TD><TD ALIGN='right'>%d</TD></TR>\n", 
        $date, $deployResult{$date}{'success'}, $deployResult{$date}{'error'},
		$deployResult{$date}{'success'} ==0 ? "0": $runTime{$date}/1000/$deployResult{$date}{'success'});
}
$XHTML .= sprintf("<TR><TH>Total</TH><TH bgcolor='green'>%d</TH><TH bgcolor='red'>%d</TH></TR>\n", $total{'success'}, $total{'error'});

$XHTML .= '</TABLE>';

my $fullProjectList = join(",",@projects);
# Get rid of non-HTML friendly characters
$fullProjectList =~ s/</&lt;/g;
$fullProjectList =~ s/>/&tt;/g;
$fullProjectList =~ s/\&/&amp;/g;

$XHTML .= qq(
<table border="3">
	<tr><th>Projects</th></tr>
);
foreach my $proj (split(",",$fullProjectList)) {
	$XHTML .= qq(<tr><td>$proj</td></tr>);
}
$XHTML .= '</table>';

#$ec->setProperty("/projects/Default/unplug/v_debug_flot.xhtml", $XHTML);

# Print out $XHTML when run from the command line
print $XHTML if $DEBUG;

#############################################################################
#
#  Calculate the Date based on now minus the number of days 
#
#############################################################################
sub calculateDate {
    my $nbDays=shift;
    return DateTime->now()->subtract(days => $nbDays)->iso8601() . ".000Z";
}