#!/usr/bin/perl
# ============================================================================
#  AVADAFY BUDGET PLATFORM
#  A full budgeting template, calculator, and all-in-one budget manager
#  Written in classic Perl — no strict, no warnings, no my declarations
# ============================================================================

# ---------- Detect Run Mode ----------
# If not running under a CGI server, start a built-in HTTP server
# so the app works with just: perl budget.pl

if (!$ENV{'GATEWAY_INTERFACE'} && !$ENV{'SERVER_SOFTWARE'}) {
    require IO::Socket::INET;

    $PORT = $ENV{'PORT'} || 8080;

    $httpd = IO::Socket::INET->new(
        LocalAddr => '0.0.0.0',
        LocalPort => $PORT,
        Proto     => 'tcp',
        Listen    => 10,
        ReuseAddr => 1,
    );

    if (!$httpd) {
        die "Cannot start server on port $PORT: $!\n";
    }

    print "=============================================\n";
    print "  Avadafy Budget Platform\n";
    print "  Running at: http://localhost:$PORT\n";
    print "  Press Ctrl+C to stop\n";
    print "=============================================\n\n";

    $SIG{'CHLD'} = 'IGNORE';

    while ($conn = $httpd->accept()) {
        $child_pid = fork();

        if (!defined $child_pid) {
            close($conn);
            next;
        }

        if ($child_pid == 0) {
            # Child handles this request
            close($httpd);

            # Read the HTTP request line
            $req_line = <$conn>;
            $req_line =~ s/\r?\n$//;
            ($http_method, $http_uri, $http_ver) = split(/\s+/, $req_line, 3);
            $http_method ||= 'GET';
            $http_uri    ||= '/';

            # Read headers
            $content_len = 0;
            while ($hdr = <$conn>) {
                $hdr =~ s/\r?\n$//;
                last if $hdr eq '';
                if ($hdr =~ /^Content-Length:\s*(\d+)/i) {
                    $content_len = $1;
                }
            }

            # Split URI into path and query string
            ($req_path, $req_qs) = split(/\?/, $http_uri, 2);
            $req_qs ||= '';

            # Respond 404 for favicon
            if ($req_path eq '/favicon.ico') {
                print $conn "HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n";
                close($conn);
                exit(0);
            }

            # Read POST body
            $post_data = '';
            if ($http_method eq 'POST' && $content_len > 0) {
                read($conn, $post_data, $content_len);
            }

            # Set CGI environment
            $ENV{'REQUEST_METHOD'} = $http_method;
            $ENV{'QUERY_STRING'}   = $req_qs;
            $ENV{'CONTENT_LENGTH'} = $content_len;
            $ENV{'GATEWAY_INTERFACE'} = 'CGI/1.1';

            # Redirect STDOUT to the client socket
            open(STDOUT, ">&" . fileno($conn));

            # HTTP status line before CGI headers
            print "HTTP/1.0 200 OK\r\n";

            # For POST requests, make body available on STDIN
            if ($http_method eq 'POST' && $content_len > 0) {
                $tmp_post = "/tmp/_budget_post_$$";
                open(POST_TMP, ">$tmp_post");
                print POST_TMP $post_data;
                close(POST_TMP);
                open(STDIN, "<$tmp_post");
                unlink($tmp_post);
            }

            # Log request to terminal
            print STDERR "$http_method $http_uri\n";

            # Fall through to CGI handler
            goto CGI_HANDLER;
        }

        # Parent closes client socket and loops
        close($conn);
    }

    exit(0);
}

CGI_HANDLER:

# ---------- CGI / Environment Setup ----------

$DATA_DIR   = "budget_data";
$USERS_FILE = "$DATA_DIR/users.dat";

if (!-d $DATA_DIR) {
    mkdir $DATA_DIR, 0755;
}

# ---------- Read CGI Input ----------

$ENV{'REQUEST_METHOD'} ||= 'GET';
$raw_input = '';

if ($ENV{'REQUEST_METHOD'} eq 'POST') {
    read(STDIN, $raw_input, $ENV{'CONTENT_LENGTH'} || 0);
} else {
    $raw_input = $ENV{'QUERY_STRING'} || '';
}

%PARAMS = ();
foreach $pair (split(/&/, $raw_input)) {
    ($key, $val) = split(/=/, $pair, 2);
    $key =~ s/\+/ /g;
    $key =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    $val =~ s/\+/ /g;
    $val =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    $PARAMS{$key} = $val;
}

$action = $PARAMS{'action'} || 'dashboard';
$user   = $PARAMS{'user'}   || 'default';

# Sanitize user to prevent path traversal and XSS
$user =~ s/[^a-zA-Z0-9_-]//g;
$user = 'default' unless $user;

# ---------- HTML Encoding Helper ----------

sub html_escape {
    ($str) = @_;
    $str =~ s/&/&amp;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;
    return $str;
}

# ---------- Data Persistence Helpers ----------

sub save_budget_data {
    ($filename, $hashref) = @_;
    $filepath = "$DATA_DIR/$filename";
    open(FH, ">$filepath") || return 0;
    foreach $k (sort keys %{$hashref}) {
        $v = $hashref->{$k};
        $v =~ s/\n/\\n/g;
        print FH "$k\t$v\n";
    }
    close(FH);
    return 1;
}

sub load_budget_data {
    ($filename) = @_;
    $filepath = "$DATA_DIR/$filename";
    %loaded = ();
    if (open(FH, "<$filepath")) {
        while ($line = <FH>) {
            chomp $line;
            ($k, $v) = split(/\t/, $line, 2);
            $v =~ s/\\n/\n/g;
            $loaded{$k} = $v;
        }
        close(FH);
    }
    return %loaded;
}

sub save_list_data {
    ($filename, $listref) = @_;
    $filepath = "$DATA_DIR/$filename";
    open(FH, ">$filepath") || return 0;
    foreach $item (@{$listref}) {
        $joined = join("\t", @{$item});
        print FH "$joined\n";
    }
    close(FH);
    return 1;
}

sub load_list_data {
    ($filename) = @_;
    $filepath = "$DATA_DIR/$filename";
    @loaded_list = ();
    if (open(FH, "<$filepath")) {
        while ($line = <FH>) {
            chomp $line;
            @fields = split(/\t/, $line);
            push @loaded_list, [@fields];
        }
        close(FH);
    }
    return @loaded_list;
}

# ---------- Budget Category Definitions ----------

@INCOME_CATEGORIES = (
    'Salary/Wages',
    'Freelance/Side Hustle',
    'Investments/Dividends',
    'Rental Income',
    'Government Benefits',
    'Gifts/Bonuses',
    'Other Income'
);

@EXPENSE_CATEGORIES = (
    'Housing/Rent',
    'Mortgage',
    'Utilities (Electric/Gas/Water)',
    'Internet/Phone',
    'Groceries',
    'Dining Out',
    'Transportation/Gas',
    'Car Payment/Insurance',
    'Health Insurance',
    'Medical/Dental',
    'Student Loans',
    'Credit Card Payments',
    'Clothing',
    'Personal Care',
    'Entertainment/Streaming',
    'Subscriptions',
    'Gym/Fitness',
    'Pet Expenses',
    'Childcare/Education',
    'Home Maintenance',
    'Savings Contribution',
    'Emergency Fund',
    'Retirement (401k/IRA)',
    'Charitable Giving',
    'Gifts',
    'Travel/Vacation',
    'Miscellaneous'
);

# ---------- Budget Template Definitions ----------

%TEMPLATE_5030_20 = (
    'name'        => '50/30/20 Rule',
    'description' => 'Allocate 50% to needs, 30% to wants, and 20% to savings & debt repayment.',
    'needs'       => 50,
    'wants'       => 30,
    'savings'     => 20,
    'needs_cats'  => 'Housing/Rent,Mortgage,Utilities (Electric/Gas/Water),Internet/Phone,Groceries,Transportation/Gas,Car Payment/Insurance,Health Insurance,Medical/Dental,Childcare/Education',
    'wants_cats'  => 'Dining Out,Clothing,Personal Care,Entertainment/Streaming,Subscriptions,Gym/Fitness,Pet Expenses,Travel/Vacation,Gifts,Miscellaneous',
    'savings_cats' => 'Savings Contribution,Emergency Fund,Retirement (401k/IRA),Student Loans,Credit Card Payments,Charitable Giving'
);

%TEMPLATE_ZERO_BASED = (
    'name'        => 'Zero-Based Budget',
    'description' => 'Every dollar gets a job. Income minus all allocated expenses equals exactly zero.',
    'housing'     => 25,
    'food'        => 15,
    'transport'   => 10,
    'utilities'   => 10,
    'insurance'   => 10,
    'debt'        => 10,
    'savings'     => 10,
    'personal'    => 5,
    'giving'      => 5
);

%TEMPLATE_ENVELOPE = (
    'name'        => 'Envelope Method',
    'description' => 'Divide cash into envelopes for each spending category. When an envelope is empty, stop spending.',
    'groceries'   => 'variable',
    'dining'      => 'variable',
    'gas'         => 'variable',
    'clothing'    => 'variable',
    'entertainment' => 'variable',
    'personal'    => 'variable',
    'gifts'       => 'variable',
    'misc'        => 'variable'
);

%TEMPLATE_PAY_YOURSELF = (
    'name'        => 'Pay Yourself First',
    'description' => 'Prioritize savings by setting aside a fixed percentage before allocating for expenses.',
    'savings_pct' => 20,
    'invest_pct'  => 10,
    'remaining'   => 70
);

# ---------- Calculation Helpers ----------

sub format_currency {
    ($amount) = @_;
    $is_negative = ($amount < 0) ? 1 : 0;
    $amount = sprintf("%.2f", abs($amount));
    $amount =~ s/\B(?=(\d{3})+(?!\d))/,/g if $amount =~ /^\d{4}/;
    return $is_negative ? "-\$$amount" : "\$$amount";
}

sub calc_percentage {
    ($part, $total) = @_;
    return 0 if $total == 0;
    return sprintf("%.1f", ($part / $total) * 100);
}

sub calc_monthly_from_annual {
    ($annual) = @_;
    return sprintf("%.2f", $annual / 12);
}

sub calc_annual_from_monthly {
    ($monthly) = @_;
    return sprintf("%.2f", $monthly * 12);
}

sub calc_compound_interest {
    ($principal, $rate, $years, $monthly_contrib) = @_;
    $monthly_rate = $rate / 100 / 12;
    $months = $years * 12;
    $total = $principal;
    for ($i = 0; $i < $months; $i++) {
        $total = ($total + $monthly_contrib) * (1 + $monthly_rate);
    }
    return sprintf("%.2f", $total);
}

sub calc_debt_payoff {
    ($balance, $rate, $monthly_payment) = @_;
    $monthly_rate = $rate / 100 / 12;
    $months = 0;
    $total_interest = 0;
    $remaining = $balance;

    while ($remaining > 0 && $months < 600) {
        $interest = $remaining * $monthly_rate;
        $total_interest += $interest;
        $remaining = $remaining + $interest - $monthly_payment;
        $months++;
        last if $monthly_payment <= $interest;
    }

    if ($monthly_payment <= ($balance * $monthly_rate)) {
        return (-1, -1);
    }

    return ($months, sprintf("%.2f", $total_interest));
}

sub calc_emergency_fund {
    ($monthly_expenses, $months_coverage) = @_;
    return sprintf("%.2f", $monthly_expenses * $months_coverage);
}

# ---------- Process Actions (Save Data) ----------

if ($action eq 'save_income') {
    %income_data = ();
    $total_income = 0;
    foreach $cat (@INCOME_CATEGORIES) {
        $param_key = $cat;
        $param_key =~ s/[^a-zA-Z0-9]/_/g;
        $val = $PARAMS{$param_key} || 0;
        $val =~ s/[^0-9.]//g;
        $income_data{$cat} = $val;
        $total_income += $val;
    }
    $income_data{'_total'} = $total_income;
    $income_data{'_month'} = $PARAMS{'month'} || 'current';
    save_budget_data("${user}_income.dat", \%income_data);
    $action = 'income';
    $save_msg = 'Income saved successfully!';
}

if ($action eq 'save_expenses') {
    %expense_data = ();
    $total_expenses = 0;
    foreach $cat (@EXPENSE_CATEGORIES) {
        $param_key = $cat;
        $param_key =~ s/[^a-zA-Z0-9]/_/g;
        $val = $PARAMS{$param_key} || 0;
        $val =~ s/[^0-9.]//g;
        $expense_data{$cat} = $val;
        $total_expenses += $val;
    }
    $expense_data{'_total'} = $total_expenses;
    $expense_data{'_month'} = $PARAMS{'month'} || 'current';
    save_budget_data("${user}_expenses.dat", \%expense_data);
    $action = 'expenses';
    $save_msg = 'Expenses saved successfully!';
}

if ($action eq 'save_goal') {
    @goals = load_list_data("${user}_goals.dat");
    $goal_name   = $PARAMS{'goal_name'}   || 'Unnamed Goal';
    $goal_target = $PARAMS{'goal_target'} || 0;
    $goal_saved  = $PARAMS{'goal_saved'}  || 0;
    $goal_date   = $PARAMS{'goal_date'}   || 'No deadline';
    push @goals, [$goal_name, $goal_target, $goal_saved, $goal_date];
    save_list_data("${user}_goals.dat", \@goals);
    $action = 'goals';
    $save_msg = 'Savings goal added!';
}

if ($action eq 'save_debt') {
    @debts = load_list_data("${user}_debts.dat");
    $debt_name    = $PARAMS{'debt_name'}    || 'Unnamed Debt';
    $debt_balance = $PARAMS{'debt_balance'} || 0;
    $debt_rate    = $PARAMS{'debt_rate'}    || 0;
    $debt_payment = $PARAMS{'debt_payment'} || 0;
    push @debts, [$debt_name, $debt_balance, $debt_rate, $debt_payment];
    save_list_data("${user}_debts.dat", \@debts);
    $action = 'debts';
    $save_msg = 'Debt entry added!';
}

if ($action eq 'delete_goal') {
    @goals = load_list_data("${user}_goals.dat");
    $del_idx = $PARAMS{'idx'};
    if (defined $del_idx && $del_idx >= 0 && $del_idx < scalar @goals) {
        splice(@goals, $del_idx, 1);
        save_list_data("${user}_goals.dat", \@goals);
    }
    $action = 'goals';
    $save_msg = 'Goal removed.';
}

if ($action eq 'delete_debt') {
    @debts = load_list_data("${user}_debts.dat");
    $del_idx = $PARAMS{'idx'};
    if (defined $del_idx && $del_idx >= 0 && $del_idx < scalar @debts) {
        splice(@debts, $del_idx, 1);
        save_list_data("${user}_debts.dat", \@debts);
    }
    $action = 'debts';
    $save_msg = 'Debt entry removed.';
}

# ---------- Load Stored Data for Display ----------

%stored_income   = load_budget_data("${user}_income.dat");
%stored_expenses = load_budget_data("${user}_expenses.dat");
@stored_goals    = load_list_data("${user}_goals.dat");
@stored_debts    = load_list_data("${user}_debts.dat");

$total_income_stored   = $stored_income{'_total'}   || 0;
$total_expenses_stored = $stored_expenses{'_total'} || 0;
$net_balance           = $total_income_stored - $total_expenses_stored;

# ---------- HTML Output ----------

print "Content-Type: text/html\n\n";

print <<'HTML_HEAD';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Avadafy Budget Platform</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
    --bg-primary: #0f0f1a;
    --bg-secondary: #1a1a2e;
    --bg-card: #16213e;
    --bg-input: #0f3460;
    --text-primary: #e0e0ff;
    --text-secondary: #a0a0cc;
    --text-muted: #6a6a99;
    --accent: #7c3aed;
    --accent-light: #a78bfa;
    --accent-glow: rgba(124, 58, 237, 0.3);
    --success: #10b981;
    --success-bg: rgba(16, 185, 129, 0.15);
    --warning: #f59e0b;
    --warning-bg: rgba(245, 158, 11, 0.15);
    --danger: #ef4444;
    --danger-bg: rgba(239, 68, 68, 0.15);
    --info: #3b82f6;
    --info-bg: rgba(59, 130, 246, 0.15);
    --border: #2a2a4a;
    --radius: 12px;
    --shadow: 0 4px 24px rgba(0,0,0,0.3);
}

body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg-primary);
    color: var(--text-primary);
    min-height: 100vh;
    line-height: 1.6;
}

/* Layout */
.app-container { display: flex; min-height: 100vh; }

.sidebar {
    width: 260px;
    background: var(--bg-secondary);
    border-right: 1px solid var(--border);
    padding: 24px 0;
    position: fixed;
    height: 100vh;
    overflow-y: auto;
    z-index: 100;
}

.sidebar-brand {
    padding: 0 24px 24px;
    border-bottom: 1px solid var(--border);
    margin-bottom: 16px;
}

.sidebar-brand h1 {
    font-size: 1.4rem;
    background: linear-gradient(135deg, var(--accent), var(--accent-light));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    font-weight: 800;
    letter-spacing: -0.5px;
}

.sidebar-brand p {
    font-size: 0.75rem;
    color: var(--text-muted);
    margin-top: 4px;
}

.nav-section {
    padding: 8px 16px;
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 1.5px;
    color: var(--text-muted);
    margin-top: 8px;
}

.nav-link {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 24px;
    color: var(--text-secondary);
    text-decoration: none;
    font-size: 0.9rem;
    transition: all 0.2s;
    border-left: 3px solid transparent;
}

.nav-link:hover {
    background: rgba(124, 58, 237, 0.1);
    color: var(--text-primary);
}

.nav-link.active {
    background: rgba(124, 58, 237, 0.15);
    color: var(--accent-light);
    border-left-color: var(--accent);
    font-weight: 600;
}

.nav-link .icon { font-size: 1.1rem; width: 24px; text-align: center; }

.main-content {
    margin-left: 260px;
    flex: 1;
    padding: 32px;
    max-width: 1100px;
}

/* Cards */
.card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 24px;
    margin-bottom: 24px;
    box-shadow: var(--shadow);
}

.card-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
    padding-bottom: 16px;
    border-bottom: 1px solid var(--border);
}

.card-header h2 {
    font-size: 1.25rem;
    font-weight: 700;
}

.card-header .badge {
    padding: 4px 12px;
    border-radius: 20px;
    font-size: 0.75rem;
    font-weight: 600;
}

/* Dashboard Stats */
.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
}

.stat-card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px;
    position: relative;
    overflow: hidden;
}

.stat-card::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 3px;
}

.stat-card.income::before { background: var(--success); }
.stat-card.expense::before { background: var(--danger); }
.stat-card.balance::before { background: var(--accent); }
.stat-card.savings::before { background: var(--info); }

.stat-label {
    font-size: 0.8rem;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: 8px;
}

.stat-value {
    font-size: 1.8rem;
    font-weight: 800;
    letter-spacing: -1px;
}

.stat-card.income .stat-value { color: var(--success); }
.stat-card.expense .stat-value { color: var(--danger); }
.stat-card.balance .stat-value { color: var(--accent-light); }
.stat-card.savings .stat-value { color: var(--info); }

.stat-sub {
    font-size: 0.75rem;
    color: var(--text-muted);
    margin-top: 4px;
}

/* Forms */
.form-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 16px;
}

.form-group { margin-bottom: 16px; }

.form-group label {
    display: block;
    font-size: 0.85rem;
    color: var(--text-secondary);
    margin-bottom: 6px;
    font-weight: 500;
}

.form-group input,
.form-group select,
.form-group textarea {
    width: 100%;
    padding: 10px 14px;
    background: var(--bg-input);
    border: 1px solid var(--border);
    border-radius: 8px;
    color: var(--text-primary);
    font-size: 0.95rem;
    transition: border-color 0.2s;
}

.form-group input:focus,
.form-group select:focus,
.form-group textarea:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 3px var(--accent-glow);
}

.form-group input[type="number"] { font-variant-numeric: tabular-nums; }

/* Buttons */
.btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 10px 20px;
    border: none;
    border-radius: 8px;
    font-size: 0.9rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s;
    text-decoration: none;
}

.btn-primary {
    background: linear-gradient(135deg, var(--accent), #6d28d9);
    color: white;
}
.btn-primary:hover { transform: translateY(-1px); box-shadow: 0 4px 16px var(--accent-glow); }

.btn-success { background: var(--success); color: white; }
.btn-success:hover { background: #059669; }

.btn-danger { background: var(--danger); color: white; }
.btn-danger:hover { background: #dc2626; }

.btn-outline {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
}
.btn-outline:hover { border-color: var(--accent); color: var(--accent-light); }

.btn-sm { padding: 6px 14px; font-size: 0.8rem; }

/* Tables */
.data-table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 16px;
}

.data-table th,
.data-table td {
    padding: 12px 16px;
    text-align: left;
    border-bottom: 1px solid var(--border);
}

.data-table th {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: var(--text-muted);
    font-weight: 600;
}

.data-table tr:hover { background: rgba(124, 58, 237, 0.05); }

.data-table .amount { font-variant-numeric: tabular-nums; font-weight: 600; }
.data-table .amount.positive { color: var(--success); }
.data-table .amount.negative { color: var(--danger); }

/* Progress Bars */
.progress-container { margin: 12px 0; }

.progress-bar {
    height: 10px;
    background: var(--bg-input);
    border-radius: 5px;
    overflow: hidden;
    position: relative;
}

.progress-fill {
    height: 100%;
    border-radius: 5px;
    transition: width 0.5s ease;
    background: linear-gradient(90deg, var(--accent), var(--accent-light));
}

.progress-fill.success { background: linear-gradient(90deg, #059669, var(--success)); }
.progress-fill.warning { background: linear-gradient(90deg, #d97706, var(--warning)); }
.progress-fill.danger { background: linear-gradient(90deg, #dc2626, var(--danger)); }

.progress-labels {
    display: flex;
    justify-content: space-between;
    font-size: 0.8rem;
    color: var(--text-muted);
    margin-top: 4px;
}

/* Budget Breakdown Chart (CSS bars) */
.bar-chart { margin: 16px 0; }

.bar-row {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 10px;
}

.bar-label {
    width: 180px;
    font-size: 0.85rem;
    color: var(--text-secondary);
    flex-shrink: 0;
    text-align: right;
}

.bar-track {
    flex: 1;
    height: 24px;
    background: var(--bg-input);
    border-radius: 6px;
    overflow: hidden;
    position: relative;
}

.bar-fill {
    height: 100%;
    border-radius: 6px;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    padding-right: 8px;
    font-size: 0.75rem;
    font-weight: 600;
    color: white;
    min-width: 40px;
    transition: width 0.6s ease;
}

.bar-amount {
    width: 100px;
    text-align: right;
    font-size: 0.85rem;
    font-variant-numeric: tabular-nums;
    color: var(--text-secondary);
    flex-shrink: 0;
}

/* Template Cards */
.template-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 20px;
}

.template-card {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 24px;
    transition: all 0.3s;
    cursor: pointer;
    position: relative;
    overflow: hidden;
}

.template-card:hover {
    border-color: var(--accent);
    transform: translateY(-2px);
    box-shadow: 0 8px 32px var(--accent-glow);
}

.template-card h3 {
    font-size: 1.1rem;
    margin-bottom: 8px;
    color: var(--accent-light);
}

.template-card p {
    font-size: 0.85rem;
    color: var(--text-muted);
    line-height: 1.5;
    margin-bottom: 16px;
}

.template-tag {
    display: inline-block;
    padding: 3px 10px;
    border-radius: 12px;
    font-size: 0.7rem;
    font-weight: 600;
    margin-right: 6px;
    margin-bottom: 6px;
}

.tag-needs { background: var(--danger-bg); color: var(--danger); }
.tag-wants { background: var(--warning-bg); color: var(--warning); }
.tag-savings { background: var(--success-bg); color: var(--success); }
.tag-info { background: var(--info-bg); color: var(--info); }

/* Calculator Results */
.calc-result {
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 20px;
    margin-top: 16px;
}

.calc-result h3 {
    font-size: 1rem;
    color: var(--accent-light);
    margin-bottom: 12px;
}

.calc-row {
    display: flex;
    justify-content: space-between;
    padding: 8px 0;
    border-bottom: 1px solid rgba(42, 42, 74, 0.5);
}

.calc-row:last-child { border-bottom: none; }
.calc-row .label { color: var(--text-secondary); font-size: 0.9rem; }
.calc-row .value { font-weight: 700; font-variant-numeric: tabular-nums; }

/* Alerts */
.alert {
    padding: 14px 20px;
    border-radius: 8px;
    margin-bottom: 20px;
    font-size: 0.9rem;
    display: flex;
    align-items: center;
    gap: 10px;
}

.alert-success { background: var(--success-bg); color: var(--success); border: 1px solid rgba(16,185,129,0.3); }
.alert-warning { background: var(--warning-bg); color: var(--warning); border: 1px solid rgba(245,158,11,0.3); }
.alert-danger { background: var(--danger-bg); color: var(--danger); border: 1px solid rgba(239,68,68,0.3); }
.alert-info { background: var(--info-bg); color: var(--info); border: 1px solid rgba(59,130,246,0.3); }

/* Summary Sections */
.summary-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 24px;
}

.pie-visual {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin: 16px 0;
}

.pie-segment {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.8rem;
    color: var(--text-secondary);
}

.pie-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    flex-shrink: 0;
}

/* Page Header */
.page-header {
    margin-bottom: 28px;
}

.page-header h1 {
    font-size: 1.6rem;
    font-weight: 800;
    margin-bottom: 4px;
}

.page-header p {
    color: var(--text-muted);
    font-size: 0.9rem;
}

/* Responsive */
@media (max-width: 768px) {
    .sidebar {
        position: fixed;
        left: -260px;
        transition: left 0.3s;
    }
    .sidebar.open { left: 0; }
    .main-content { margin-left: 0; padding: 16px; }
    .stats-grid { grid-template-columns: 1fr 1fr; }
    .form-grid { grid-template-columns: 1fr; }
    .summary-grid { grid-template-columns: 1fr; }
    .bar-label { width: 120px; font-size: 0.75rem; }
    .mobile-toggle {
        display: block !important;
        position: fixed;
        top: 12px;
        left: 12px;
        z-index: 200;
        background: var(--accent);
        color: white;
        border: none;
        border-radius: 8px;
        padding: 8px 12px;
        font-size: 1.2rem;
        cursor: pointer;
    }
}

.mobile-toggle { display: none; }

/* Animations */
@keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
.fade-in { animation: fadeIn 0.4s ease-out; }

/* Print Styles */
@media print {
    .sidebar, .mobile-toggle, .btn, form { display: none !important; }
    .main-content { margin-left: 0; }
    body { background: white; color: black; }
    .card { border: 1px solid #ccc; box-shadow: none; }
}
</style>
</head>
<body>
HTML_HEAD

# ---------- Mobile Toggle ----------

print '<button class="mobile-toggle" onclick="document.querySelector(\'.sidebar\').classList.toggle(\'open\')">&#9776;</button>';
print "\n";

# ---------- Sidebar Navigation ----------

print '<div class="app-container">';
print '<nav class="sidebar">';
print '<div class="sidebar-brand">';
print '<h1>Avadafy Budget</h1>';
print '<p>All-in-One Budget Platform</p>';
print '</div>';

print '<div class="nav-section">Overview</div>';
print_nav_link('dashboard', 'Dashboard', $action);
print_nav_link('summary', 'Budget Summary', $action);

print '<div class="nav-section">Manage</div>';
print_nav_link('income', 'Income', $action);
print_nav_link('expenses', 'Expenses', $action);
print_nav_link('goals', 'Savings Goals', $action);
print_nav_link('debts', 'Debt Tracker', $action);

print '<div class="nav-section">Tools</div>';
print_nav_link('templates', 'Budget Templates', $action);
print_nav_link('calculator', 'Calculators', $action);
print_nav_link('reports', 'Reports', $action);
print_nav_link('export', 'Export / Print', $action);

print '</nav>';

# ---------- Main Content Area ----------

print '<main class="main-content fade-in">';

# Success message
if ($save_msg) {
    print "<div class=\"alert alert-success\">$save_msg</div>";
}

# ---------- DASHBOARD PAGE ----------

if ($action eq 'dashboard') {
    render_dashboard();
}
elsif ($action eq 'income') {
    render_income_page();
}
elsif ($action eq 'expenses') {
    render_expenses_page();
}
elsif ($action eq 'summary') {
    render_summary_page();
}
elsif ($action eq 'goals') {
    render_goals_page();
}
elsif ($action eq 'debts') {
    render_debts_page();
}
elsif ($action eq 'templates') {
    render_templates_page();
}
elsif ($action eq 'calculator') {
    render_calculator_page();
}
elsif ($action eq 'reports') {
    render_reports_page();
}
elsif ($action eq 'export') {
    render_export_page();
}

print '</main>';
print '</div>';

# ---------- JavaScript ----------

print <<'HTML_FOOT';
<script>
// Live calculation helpers
function updateTotal(prefix, fields, totalId) {
    var total = 0;
    fields.forEach(function(f) {
        var el = document.getElementById(prefix + f);
        if (el) total += parseFloat(el.value) || 0;
    });
    var totalEl = document.getElementById(totalId);
    if (totalEl) totalEl.textContent = '$' + total.toFixed(2);
    return total;
}

// Calculator: Compound Interest
function calcCompound() {
    var p = parseFloat(document.getElementById('ci_principal').value) || 0;
    var r = parseFloat(document.getElementById('ci_rate').value) || 0;
    var y = parseFloat(document.getElementById('ci_years').value) || 0;
    var m = parseFloat(document.getElementById('ci_monthly').value) || 0;
    var mr = r / 100 / 12;
    var months = y * 12;
    var total = p;
    for (var i = 0; i < months; i++) {
        total = (total + m) * (1 + mr);
    }
    var totalContrib = p + (m * months);
    var interest = total - totalContrib;
    document.getElementById('ci_result_total').textContent = '$' + total.toFixed(2);
    document.getElementById('ci_result_contrib').textContent = '$' + totalContrib.toFixed(2);
    document.getElementById('ci_result_interest').textContent = '$' + interest.toFixed(2);
    document.getElementById('ci_results').style.display = 'block';
}

// Calculator: Debt Payoff
function calcDebt() {
    var bal = parseFloat(document.getElementById('dp_balance').value) || 0;
    var rate = parseFloat(document.getElementById('dp_rate').value) || 0;
    var pmt = parseFloat(document.getElementById('dp_payment').value) || 0;
    var mr = rate / 100 / 12;
    var months = 0;
    var totalInt = 0;
    var rem = bal;
    if (pmt <= rem * mr) {
        document.getElementById('dp_result_months').textContent = 'Never (payment too low)';
        document.getElementById('dp_result_interest').textContent = 'N/A';
        document.getElementById('dp_result_total').textContent = 'N/A';
        document.getElementById('dp_results').style.display = 'block';
        return;
    }
    while (rem > 0 && months < 600) {
        var intCharge = rem * mr;
        totalInt += intCharge;
        rem = rem + intCharge - pmt;
        months++;
    }
    var years = Math.floor(months / 12);
    var remMonths = months % 12;
    var timeStr = '';
    if (years > 0) timeStr += years + ' year' + (years > 1 ? 's' : '') + ' ';
    timeStr += remMonths + ' month' + (remMonths !== 1 ? 's' : '');
    document.getElementById('dp_result_months').textContent = timeStr + ' (' + months + ' months)';
    document.getElementById('dp_result_interest').textContent = '$' + totalInt.toFixed(2);
    document.getElementById('dp_result_total').textContent = '$' + (bal + totalInt).toFixed(2);
    document.getElementById('dp_results').style.display = 'block';
}

// Calculator: Emergency Fund
function calcEmergency() {
    var exp = parseFloat(document.getElementById('ef_expenses').value) || 0;
    var mos = parseFloat(document.getElementById('ef_months').value) || 6;
    var saved = parseFloat(document.getElementById('ef_saved').value) || 0;
    var target = exp * mos;
    var needed = target - saved;
    if (needed < 0) needed = 0;
    document.getElementById('ef_result_target').textContent = '$' + target.toFixed(2);
    document.getElementById('ef_result_saved').textContent = '$' + saved.toFixed(2);
    document.getElementById('ef_result_needed').textContent = '$' + needed.toFixed(2);
    var pct = target > 0 ? ((saved / target) * 100) : 0;
    if (pct > 100) pct = 100;
    document.getElementById('ef_progress_fill').style.width = pct + '%';
    document.getElementById('ef_progress_pct').textContent = pct.toFixed(1) + '%';
    document.getElementById('ef_results').style.display = 'block';
}

// Calculator: 50/30/20 Breakdown
function calc503020() {
    var income = parseFloat(document.getElementById('rule_income').value) || 0;
    document.getElementById('rule_needs').textContent = '$' + (income * 0.50).toFixed(2);
    document.getElementById('rule_wants').textContent = '$' + (income * 0.30).toFixed(2);
    document.getElementById('rule_savings').textContent = '$' + (income * 0.20).toFixed(2);
    document.getElementById('rule_results').style.display = 'block';
}

// Print page
function printBudget() { window.print(); }

// Sidebar toggle on mobile
document.querySelectorAll('.nav-link').forEach(function(el) {
    el.addEventListener('click', function() {
        var sb = document.querySelector('.sidebar');
        if (sb) sb.classList.remove('open');
    });
});
</script>
</body>
</html>
HTML_FOOT

# ============================================================================
#  PAGE RENDER SUBROUTINES
# ============================================================================

sub print_nav_link {
    ($link_action, $label, $current_action) = @_;
    $active_class = ($link_action eq $current_action) ? ' active' : '';

    %icons = (
        'dashboard'  => '&#x1F4CA;',
        'summary'    => '&#x1F4CB;',
        'income'     => '&#x1F4B0;',
        'expenses'   => '&#x1F4B8;',
        'goals'      => '&#x1F3AF;',
        'debts'      => '&#x1F4B3;',
        'templates'  => '&#x1F4D0;',
        'calculator' => '&#x1F5A9;',
        'reports'    => '&#x1F4C8;',
        'export'     => '&#x1F5B6;',
    );

    $icon = $icons{$link_action} || '&#x25CF;';
    $safe_user = html_escape($user);
    print "<a class=\"nav-link$active_class\" href=\"?action=$link_action&user=$safe_user\">";
    print "<span class=\"icon\">$icon</span> $label</a>\n";
}

# ---------- Dashboard ----------

sub render_dashboard {
    print '<div class="page-header">';
    print '<h1>Budget Dashboard</h1>';
    print '<p>Your financial overview at a glance</p>';
    print '</div>';

    # Stats cards
    $savings_total = 0;
    foreach $g (@stored_goals) {
        $savings_total += ($g->[2] || 0);
    }

    print '<div class="stats-grid">';

    print '<div class="stat-card income">';
    print '<div class="stat-label">Total Income</div>';
    print '<div class="stat-value">' . format_currency($total_income_stored) . '</div>';
    print '<div class="stat-sub">Monthly</div>';
    print '</div>';

    print '<div class="stat-card expense">';
    print '<div class="stat-label">Total Expenses</div>';
    print '<div class="stat-value">' . format_currency($total_expenses_stored) . '</div>';
    print '<div class="stat-sub">Monthly</div>';
    print '</div>';

    $balance_class = $net_balance >= 0 ? 'balance' : 'expense';
    print "<div class=\"stat-card $balance_class\">";
    print '<div class="stat-label">Net Balance</div>';
    print '<div class="stat-value">' . format_currency($net_balance) . '</div>';
    $pct = calc_percentage($net_balance, $total_income_stored);
    print "<div class=\"stat-sub\">${pct}% of income</div>";
    print '</div>';

    print '<div class="stat-card savings">';
    print '<div class="stat-label">Total Saved</div>';
    print '<div class="stat-value">' . format_currency($savings_total) . '</div>';
    print '<div class="stat-sub">Across ' . scalar(@stored_goals) . ' goal(s)</div>';
    print '</div>';

    print '</div>';

    # Budget health
    print '<div class="card">';
    print '<div class="card-header"><h2>Budget Health</h2></div>';

    if ($total_income_stored > 0) {
        $spend_pct = calc_percentage($total_expenses_stored, $total_income_stored);
        $save_pct = calc_percentage($net_balance, $total_income_stored);

        if ($spend_pct > 100) {
            print '<div class="alert alert-danger">You are spending more than you earn! Consider cutting expenses.</div>';
        } elsif ($spend_pct > 90) {
            print '<div class="alert alert-warning">You are spending over 90% of your income. Try to reduce non-essential spending.</div>';
        } elsif ($spend_pct > 70) {
            print '<div class="alert alert-info">Spending is moderate. Look for areas to save more.</div>';
        } else {
            print '<div class="alert alert-success">Great job! You have a healthy spending-to-income ratio.</div>';
        }

        print '<div class="progress-container">';
        print '<div style="display:flex;justify-content:space-between;margin-bottom:6px;">';
        print "<span style=\"font-size:0.85rem;\">Spending: ${spend_pct}% of income</span>";
        print "<span style=\"font-size:0.85rem;\">Remaining: ${save_pct}%</span>";
        print '</div>';

        $bar_class = $spend_pct > 100 ? 'danger' : ($spend_pct > 80 ? 'warning' : 'success');
        $bar_width = $spend_pct > 100 ? 100 : $spend_pct;
        print '<div class="progress-bar">';
        print "<div class=\"progress-fill $bar_class\" style=\"width:${bar_width}%\"></div>";
        print '</div></div>';
    } else {
        print '<div class="alert alert-info">Enter your income and expenses to see your budget health.</div>';
    }
    print '</div>';

    # Quick expense breakdown
    if ($total_expenses_stored > 0) {
        print '<div class="card">';
        print '<div class="card-header"><h2>Expense Breakdown</h2></div>';
        print '<div class="bar-chart">';

        @colors = ('#7c3aed','#3b82f6','#10b981','#f59e0b','#ef4444','#ec4899','#8b5cf6','#06b6d4','#84cc16','#f97316');
        $color_idx = 0;

        foreach $cat (sort keys %stored_expenses) {
            next if $cat =~ /^_/;
            $val = $stored_expenses{$cat};
            next unless $val > 0;
            $pct = calc_percentage($val, $total_expenses_stored);
            $color = $colors[$color_idx % scalar(@colors)];
            $color_idx++;

            print '<div class="bar-row">';
            print "<div class=\"bar-label\">$cat</div>";
            print '<div class="bar-track">';
            print "<div class=\"bar-fill\" style=\"width:${pct}%;background:${color};\">${pct}%</div>";
            print '</div>';
            print '<div class="bar-amount">' . format_currency($val) . '</div>';
            print '</div>';
        }
        print '</div></div>';
    }

    # Recent goals
    if (scalar @stored_goals > 0) {
        print '<div class="card">';
        print '<div class="card-header"><h2>Savings Goals Progress</h2></div>';
        foreach $g (@stored_goals) {
            $g_name   = html_escape($g->[0]);
            $g_target = $g->[1] || 1;
            $g_saved  = $g->[2] || 0;
            $g_pct    = calc_percentage($g_saved, $g_target);
            $g_pct    = 100 if $g_pct > 100;

            $p_class = $g_pct >= 100 ? 'success' : ($g_pct >= 50 ? '' : 'warning');
            print "<div style=\"margin-bottom:16px;\">";
            print "<div style=\"display:flex;justify-content:space-between;margin-bottom:4px;\">";
            print "<span style=\"font-weight:600;\">$g_name</span>";
            print "<span style=\"color:var(--text-muted);\">" . format_currency($g_saved) . " / " . format_currency($g_target) . "</span>";
            print "</div>";
            print '<div class="progress-bar">';
            print "<div class=\"progress-fill $p_class\" style=\"width:${g_pct}%\"></div>";
            print '</div>';
            print "<div class=\"progress-labels\"><span>${g_pct}% complete</span></div>";
            print '</div>';
        }
        print '</div>';
    }

    # Debt overview
    if (scalar @stored_debts > 0) {
        $total_debt = 0;
        foreach $d (@stored_debts) { $total_debt += ($d->[1] || 0); }

        print '<div class="card">';
        print '<div class="card-header"><h2>Debt Overview</h2>';
        print '<span class="badge" style="background:var(--danger-bg);color:var(--danger);">Total: ' . format_currency($total_debt) . '</span>';
        print '</div>';
        print '<table class="data-table">';
        print '<tr><th>Debt</th><th>Balance</th><th>APR</th><th>Monthly Payment</th></tr>';
        foreach $d (@stored_debts) {
            print '<tr>';
            print "<td>" . html_escape($d->[0]) . "</td>";
            print '<td class="amount negative">' . format_currency($d->[1]) . '</td>';
            print "<td>" . html_escape($d->[2]) . "%</td>";
            print '<td>' . format_currency($d->[3]) . '</td>';
            print '</tr>';
        }
        print '</table></div>';
    }
}

# ---------- Income Page ----------

sub render_income_page {
    print '<div class="page-header">';
    print '<h1>Income Manager</h1>';
    print '<p>Track all sources of monthly income</p>';
    print '</div>';

    print '<div class="card">';
    print '<div class="card-header"><h2>Monthly Income Sources</h2>';
    print '<span id="income_total_display" class="badge" style="background:var(--success-bg);color:var(--success);font-size:0.9rem;">';
    print 'Total: ' . format_currency($total_income_stored);
    print '</span></div>';

    $safe_user = html_escape($user);
    print "<form method=\"POST\" action=\"?action=save_income&user=$safe_user\">";
    print '<input type="hidden" name="action" value="save_income">';
    print "<input type=\"hidden\" name=\"user\" value=\"$safe_user\">";
    print '<div class="form-grid">';

    foreach $cat (@INCOME_CATEGORIES) {
        $param_key = $cat;
        $param_key =~ s/[^a-zA-Z0-9]/_/g;
        $stored_val = $stored_income{$cat} || '';

        print '<div class="form-group">';
        print "<label>$cat</label>";
        print "<input type=\"number\" step=\"0.01\" min=\"0\" name=\"$param_key\" id=\"inc_$param_key\" value=\"$stored_val\" placeholder=\"0.00\">";
        print '</div>';
    }

    print '</div>';
    print '<div style="margin-top:20px;display:flex;gap:12px;">';
    print '<button type="submit" class="btn btn-success">Save Income</button>';
    print '<a href="?action=dashboard&user=' . $user . '" class="btn btn-outline">Cancel</a>';
    print '</div>';
    print '</form></div>';

    # Annual projection
    if ($total_income_stored > 0) {
        $annual = calc_annual_from_monthly($total_income_stored);
        print '<div class="card">';
        print '<div class="card-header"><h2>Income Projection</h2></div>';
        print '<div class="stats-grid">';
        print '<div class="stat-card income"><div class="stat-label">Weekly</div>';
        print '<div class="stat-value">' . format_currency($total_income_stored / 4.33) . '</div></div>';
        print '<div class="stat-card income"><div class="stat-label">Bi-Weekly</div>';
        print '<div class="stat-value">' . format_currency($total_income_stored / 2.17) . '</div></div>';
        print '<div class="stat-card income"><div class="stat-label">Monthly</div>';
        print '<div class="stat-value">' . format_currency($total_income_stored) . '</div></div>';
        print '<div class="stat-card income"><div class="stat-label">Annual</div>';
        print '<div class="stat-value">' . format_currency($annual) . '</div></div>';
        print '</div></div>';
    }
}

# ---------- Expenses Page ----------

sub render_expenses_page {
    print '<div class="page-header">';
    print '<h1>Expense Manager</h1>';
    print '<p>Track every dollar you spend across categories</p>';
    print '</div>';

    print '<div class="card">';
    print '<div class="card-header"><h2>Monthly Expenses</h2>';
    print '<span class="badge" style="background:var(--danger-bg);color:var(--danger);font-size:0.9rem;">';
    print 'Total: ' . format_currency($total_expenses_stored);
    print '</span></div>';

    $safe_user = html_escape($user);
    print "<form method=\"POST\" action=\"?action=save_expenses&user=$safe_user\">";
    print '<input type="hidden" name="action" value="save_expenses">';
    print "<input type=\"hidden\" name=\"user\" value=\"$safe_user\">";
    print '<div class="form-grid">';

    foreach $cat (@EXPENSE_CATEGORIES) {
        $param_key = $cat;
        $param_key =~ s/[^a-zA-Z0-9]/_/g;
        $stored_val = $stored_expenses{$cat} || '';

        print '<div class="form-group">';
        print "<label>$cat</label>";
        print "<input type=\"number\" step=\"0.01\" min=\"0\" name=\"$param_key\" id=\"exp_$param_key\" value=\"$stored_val\" placeholder=\"0.00\">";
        print '</div>';
    }

    print '</div>';
    print '<div style="margin-top:20px;display:flex;gap:12px;">';
    print '<button type="submit" class="btn btn-danger">Save Expenses</button>';
    print '<a href="?action=dashboard&user=' . $user . '" class="btn btn-outline">Cancel</a>';
    print '</div>';
    print '</form></div>';
}

# ---------- Summary Page ----------

sub render_summary_page {
    print '<div class="page-header">';
    print '<h1>Budget Summary</h1>';
    print '<p>Complete breakdown of your monthly budget</p>';
    print '</div>';

    # Overview cards
    print '<div class="stats-grid">';
    print '<div class="stat-card income"><div class="stat-label">Income</div>';
    print '<div class="stat-value">' . format_currency($total_income_stored) . '</div></div>';
    print '<div class="stat-card expense"><div class="stat-label">Expenses</div>';
    print '<div class="stat-value">' . format_currency($total_expenses_stored) . '</div></div>';
    $nb_class = $net_balance >= 0 ? 'balance' : 'expense';
    print "<div class=\"stat-card $nb_class\"><div class=\"stat-label\">Net</div>";
    print '<div class="stat-value">' . format_currency($net_balance) . '</div></div>';
    print '</div>';

    # Detailed income table
    print '<div class="summary-grid">';
    print '<div class="card">';
    print '<div class="card-header"><h2>Income Details</h2></div>';
    print '<table class="data-table">';
    print '<tr><th>Source</th><th>Amount</th><th>% of Total</th></tr>';
    foreach $cat (@INCOME_CATEGORIES) {
        $val = $stored_income{$cat} || 0;
        next unless $val > 0;
        $pct = calc_percentage($val, $total_income_stored);
        print '<tr>';
        print "<td>$cat</td>";
        print '<td class="amount positive">' . format_currency($val) . '</td>';
        print "<td>${pct}%</td>";
        print '</tr>';
    }
    print '<tr style="font-weight:700;border-top:2px solid var(--border);">';
    print '<td>Total</td>';
    print '<td class="amount positive">' . format_currency($total_income_stored) . '</td>';
    print '<td>100%</td>';
    print '</tr></table></div>';

    # Detailed expense table
    print '<div class="card">';
    print '<div class="card-header"><h2>Expense Details</h2></div>';
    print '<table class="data-table">';
    print '<tr><th>Category</th><th>Amount</th><th>% of Total</th></tr>';
    foreach $cat (@EXPENSE_CATEGORIES) {
        $val = $stored_expenses{$cat} || 0;
        next unless $val > 0;
        $pct = calc_percentage($val, $total_expenses_stored);
        print '<tr>';
        print "<td>$cat</td>";
        print '<td class="amount negative">' . format_currency($val) . '</td>';
        print "<td>${pct}%</td>";
        print '</tr>';
    }
    print '<tr style="font-weight:700;border-top:2px solid var(--border);">';
    print '<td>Total</td>';
    print '<td class="amount negative">' . format_currency($total_expenses_stored) . '</td>';
    print '<td>100%</td>';
    print '</tr></table></div>';
    print '</div>';

    # 50/30/20 Analysis
    if ($total_income_stored > 0 && $total_expenses_stored > 0) {
        print '<div class="card">';
        print '<div class="card-header"><h2>50/30/20 Rule Analysis</h2></div>';

        # Categorize expenses into needs/wants/savings
        $needs_total = 0;
        $wants_total = 0;
        $savings_cat_total = 0;

        @needs_list = split(/,/, $TEMPLATE_5030_20{'needs_cats'});
        @wants_list = split(/,/, $TEMPLATE_5030_20{'wants_cats'});
        @savings_list = split(/,/, $TEMPLATE_5030_20{'savings_cats'});

        %needs_map = map { $_ => 1 } @needs_list;
        %wants_map = map { $_ => 1 } @wants_list;
        %savings_map = map { $_ => 1 } @savings_list;

        foreach $cat (@EXPENSE_CATEGORIES) {
            $val = $stored_expenses{$cat} || 0;
            if ($needs_map{$cat}) { $needs_total += $val; }
            elsif ($wants_map{$cat}) { $wants_total += $val; }
            elsif ($savings_map{$cat}) { $savings_cat_total += $val; }
            else { $wants_total += $val; }
        }

        $ideal_needs = $total_income_stored * 0.50;
        $ideal_wants = $total_income_stored * 0.30;
        $ideal_savings = $total_income_stored * 0.20;

        $needs_pct = calc_percentage($needs_total, $total_income_stored);
        $wants_pct = calc_percentage($wants_total, $total_income_stored);
        $savings_pct_val = calc_percentage($savings_cat_total, $total_income_stored);

        print '<div class="stats-grid">';

        $needs_color = $needs_pct > 55 ? 'danger' : ($needs_pct > 50 ? 'warning' : 'success');
        print "<div class=\"stat-card\"><div class=\"stat-label\">Needs (Target: 50%)</div>";
        print "<div class=\"stat-value\" style=\"color:var(--$needs_color);\">${needs_pct}%</div>";
        print '<div class="stat-sub">' . format_currency($needs_total) . ' / ' . format_currency($ideal_needs) . '</div></div>';

        $wants_color = $wants_pct > 35 ? 'danger' : ($wants_pct > 30 ? 'warning' : 'success');
        print "<div class=\"stat-card\"><div class=\"stat-label\">Wants (Target: 30%)</div>";
        print "<div class=\"stat-value\" style=\"color:var(--$wants_color);\">${wants_pct}%</div>";
        print '<div class="stat-sub">' . format_currency($wants_total) . ' / ' . format_currency($ideal_wants) . '</div></div>';

        $sav_color = $savings_pct_val < 15 ? 'danger' : ($savings_pct_val < 20 ? 'warning' : 'success');
        print "<div class=\"stat-card\"><div class=\"stat-label\">Savings (Target: 20%)</div>";
        print "<div class=\"stat-value\" style=\"color:var(--$sav_color);\">${savings_pct_val}%</div>";
        print '<div class="stat-sub">' . format_currency($savings_cat_total) . ' / ' . format_currency($ideal_savings) . '</div></div>';

        print '</div></div>';
    }
}

# ---------- Savings Goals Page ----------

sub render_goals_page {
    print '<div class="page-header">';
    print '<h1>Savings Goals</h1>';
    print '<p>Set targets and track your progress toward financial milestones</p>';
    print '</div>';

    # Add new goal form
    print '<div class="card">';
    print '<div class="card-header"><h2>Add New Goal</h2></div>';
    $safe_user = html_escape($user);
    print "<form method=\"POST\" action=\"?action=save_goal&user=$safe_user\">";
    print '<input type="hidden" name="action" value="save_goal">';
    print "<input type=\"hidden\" name=\"user\" value=\"$safe_user\">";
    print '<div class="form-grid">';
    print '<div class="form-group"><label>Goal Name</label>';
    print '<input type="text" name="goal_name" placeholder="e.g., Emergency Fund, Vacation, New Car" required></div>';
    print '<div class="form-group"><label>Target Amount ($)</label>';
    print '<input type="number" step="0.01" min="0" name="goal_target" placeholder="10000.00" required></div>';
    print '<div class="form-group"><label>Already Saved ($)</label>';
    print '<input type="number" step="0.01" min="0" name="goal_saved" placeholder="0.00" value="0"></div>';
    print '<div class="form-group"><label>Target Date</label>';
    print '<input type="date" name="goal_date"></div>';
    print '</div>';
    print '<button type="submit" class="btn btn-primary" style="margin-top:12px;">Add Goal</button>';
    print '</form></div>';

    # List goals
    if (scalar @stored_goals > 0) {
        print '<div class="card">';
        print '<div class="card-header"><h2>Your Goals</h2>';
        print '<span class="badge" style="background:var(--info-bg);color:var(--info);">' . scalar(@stored_goals) . ' goal(s)</span></div>';

        foreach $idx (0 .. $#stored_goals) {
            $g = $stored_goals[$idx];
            $g_name   = html_escape($g->[0] || 'Unnamed');
            $g_target = $g->[1] || 1;
            $g_saved  = $g->[2] || 0;
            $g_date   = $g->[3] || 'No deadline';
            $g_needed = $g_target - $g_saved;
            $g_needed = 0 if $g_needed < 0;
            $g_pct    = calc_percentage($g_saved, $g_target);
            $g_pct    = 100 if $g_pct > 100;

            $p_class = $g_pct >= 100 ? 'success' : ($g_pct >= 50 ? '' : 'warning');
            $status_text = $g_pct >= 100 ? 'Complete!' : format_currency($g_needed) . ' to go';

            print '<div style="padding:16px;background:var(--bg-secondary);border-radius:8px;margin-bottom:12px;">';
            print '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">';
            print "<div><strong style=\"font-size:1.05rem;\">$g_name</strong>";
            print " <span style=\"color:var(--text-muted);font-size:0.8rem;\">Due: $g_date</span></div>";
            print "<div style=\"display:flex;gap:8px;align-items:center;\">";
            print "<span style=\"font-size:0.85rem;color:var(--text-muted);\">$status_text</span>";
            $safe_user = html_escape($user);
            print "<a href=\"?action=delete_goal&idx=$idx&user=$safe_user\" class=\"btn btn-danger btn-sm\" onclick=\"return confirm('Delete this goal?');\">Remove</a>";
            print '</div></div>';
            print '<div style="display:flex;justify-content:space-between;font-size:0.85rem;margin-bottom:4px;">';
            print '<span>' . format_currency($g_saved) . ' saved</span>';
            print '<span>' . format_currency($g_target) . ' target</span>';
            print '</div>';
            print '<div class="progress-bar">';
            print "<div class=\"progress-fill $p_class\" style=\"width:${g_pct}%\"></div>";
            print '</div>';
            print "<div class=\"progress-labels\"><span>${g_pct}% complete</span></div>";
            print '</div>';
        }
        print '</div>';
    }
}

# ---------- Debts Page ----------

sub render_debts_page {
    print '<div class="page-header">';
    print '<h1>Debt Tracker</h1>';
    print '<p>Monitor balances, interest rates, and payoff timelines</p>';
    print '</div>';

    # Add new debt form
    print '<div class="card">';
    print '<div class="card-header"><h2>Add Debt Entry</h2></div>';
    $safe_user = html_escape($user);
    print "<form method=\"POST\" action=\"?action=save_debt&user=$safe_user\">";
    print '<input type="hidden" name="action" value="save_debt">';
    print "<input type=\"hidden\" name=\"user\" value=\"$safe_user\">";
    print '<div class="form-grid">';
    print '<div class="form-group"><label>Debt Name</label>';
    print '<input type="text" name="debt_name" placeholder="e.g., Credit Card, Student Loan" required></div>';
    print '<div class="form-group"><label>Balance ($)</label>';
    print '<input type="number" step="0.01" min="0" name="debt_balance" placeholder="5000.00" required></div>';
    print '<div class="form-group"><label>Interest Rate (APR %)</label>';
    print '<input type="number" step="0.01" min="0" name="debt_rate" placeholder="18.99" required></div>';
    print '<div class="form-group"><label>Monthly Payment ($)</label>';
    print '<input type="number" step="0.01" min="0" name="debt_payment" placeholder="200.00" required></div>';
    print '</div>';
    print '<button type="submit" class="btn btn-primary" style="margin-top:12px;">Add Debt</button>';
    print '</form></div>';

    # List debts
    if (scalar @stored_debts > 0) {
        $total_debt = 0;
        $total_monthly_debt = 0;
        foreach $d (@stored_debts) {
            $total_debt += ($d->[1] || 0);
            $total_monthly_debt += ($d->[3] || 0);
        }

        print '<div class="card">';
        print '<div class="card-header"><h2>Your Debts</h2>';
        print '<span class="badge" style="background:var(--danger-bg);color:var(--danger);">Total: ' . format_currency($total_debt) . '</span></div>';

        print '<table class="data-table">';
        print '<tr><th>Name</th><th>Balance</th><th>APR</th><th>Payment</th><th>Payoff Time</th><th>Total Interest</th><th></th></tr>';

        foreach $idx (0 .. $#stored_debts) {
            $d = $stored_debts[$idx];
            ($payoff_months, $payoff_interest) = calc_debt_payoff($d->[1], $d->[2], $d->[3]);

            if ($payoff_months < 0) {
                $payoff_str = '<span style="color:var(--danger);">Never</span>';
                $interest_str = 'N/A';
            } else {
                $years_p = int($payoff_months / 12);
                $mos_p   = $payoff_months % 12;
                $payoff_str = '';
                $payoff_str .= "${years_p}y " if $years_p > 0;
                $payoff_str .= "${mos_p}m";
                $interest_str = format_currency($payoff_interest);
            }

            print '<tr>';
            print "<td><strong>" . html_escape($d->[0]) . "</strong></td>";
            print '<td class="amount negative">' . format_currency($d->[1]) . '</td>';
            print "<td>$d->[2]%</td>";
            print '<td>' . format_currency($d->[3]) . '</td>';
            print "<td>$payoff_str</td>";
            print "<td>$interest_str</td>";
            $safe_user = html_escape($user);
            print "<td><a href=\"?action=delete_debt&idx=$idx&user=$safe_user\" class=\"btn btn-danger btn-sm\" onclick=\"return confirm('Delete this debt?');\">Remove</a></td>";
            print '</tr>';
        }

        print '<tr style="font-weight:700;border-top:2px solid var(--border);">';
        print '<td>Totals</td>';
        print '<td class="amount negative">' . format_currency($total_debt) . '</td>';
        print '<td></td>';
        print '<td>' . format_currency($total_monthly_debt) . '</td>';
        print '<td colspan="3"></td>';
        print '</tr>';
        print '</table></div>';

        # Debt-to-income ratio
        if ($total_income_stored > 0) {
            $dti = calc_percentage($total_monthly_debt, $total_income_stored);
            print '<div class="card">';
            print '<div class="card-header"><h2>Debt-to-Income Ratio</h2></div>';
            $dti_color = $dti > 40 ? 'danger' : ($dti > 30 ? 'warning' : 'success');
            print "<div class=\"stat-value\" style=\"color:var(--$dti_color);font-size:2.5rem;text-align:center;padding:20px 0;\">${dti}%</div>";
            print '<div class="progress-bar" style="max-width:500px;margin:0 auto;">';
            $dti_width = $dti > 100 ? 100 : $dti;
            print "<div class=\"progress-fill $dti_color\" style=\"width:${dti_width}%\"></div>";
            print '</div>';
            print '<div style="text-align:center;margin-top:12px;color:var(--text-muted);font-size:0.85rem;">';
            if ($dti > 40) {
                print 'High ratio. Focus on debt repayment.';
            } elsif ($dti > 30) {
                print 'Moderate ratio. Consider paying down high-interest debts.';
            } else {
                print 'Healthy ratio. Keep up the good work!';
            }
            print '</div></div>';
        }
    }
}

# ---------- Templates Page ----------

sub render_templates_page {
    print '<div class="page-header">';
    print '<h1>Budget Templates</h1>';
    print '<p>Choose a proven budgeting strategy to structure your finances</p>';
    print '</div>';

    print '<div class="template-grid">';

    # 50/30/20
    print '<div class="template-card">';
    print '<h3>' . $TEMPLATE_5030_20{'name'} . '</h3>';
    print '<p>' . $TEMPLATE_5030_20{'description'} . '</p>';
    print '<div>';
    print '<span class="template-tag tag-needs">Needs 50%</span>';
    print '<span class="template-tag tag-wants">Wants 30%</span>';
    print '<span class="template-tag tag-savings">Savings 20%</span>';
    print '</div>';
    if ($total_income_stored > 0) {
        print '<div style="margin-top:16px;padding-top:16px;border-top:1px solid var(--border);">';
        print '<div class="calc-row"><span class="label">Needs budget:</span>';
        print '<span class="value" style="color:var(--danger);">' . format_currency($total_income_stored * 0.50) . '</span></div>';
        print '<div class="calc-row"><span class="label">Wants budget:</span>';
        print '<span class="value" style="color:var(--warning);">' . format_currency($total_income_stored * 0.30) . '</span></div>';
        print '<div class="calc-row"><span class="label">Savings budget:</span>';
        print '<span class="value" style="color:var(--success);">' . format_currency($total_income_stored * 0.20) . '</span></div>';
        print '</div>';
    }
    print '</div>';

    # Zero-Based
    print '<div class="template-card">';
    print '<h3>' . $TEMPLATE_ZERO_BASED{'name'} . '</h3>';
    print '<p>' . $TEMPLATE_ZERO_BASED{'description'} . '</p>';
    print '<div>';
    print '<span class="template-tag tag-needs">Housing 25%</span>';
    print '<span class="template-tag tag-info">Food 15%</span>';
    print '<span class="template-tag tag-wants">Transport 10%</span>';
    print '<span class="template-tag tag-savings">Savings 10%</span>';
    print '</div>';
    if ($total_income_stored > 0) {
        print '<div style="margin-top:16px;padding-top:16px;border-top:1px solid var(--border);">';
        print '<div class="calc-row"><span class="label">Housing:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.25) . '</span></div>';
        print '<div class="calc-row"><span class="label">Food:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.15) . '</span></div>';
        print '<div class="calc-row"><span class="label">Transport:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.10) . '</span></div>';
        print '<div class="calc-row"><span class="label">Utilities:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.10) . '</span></div>';
        print '<div class="calc-row"><span class="label">Insurance:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.10) . '</span></div>';
        print '<div class="calc-row"><span class="label">Debt:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.10) . '</span></div>';
        print '<div class="calc-row"><span class="label">Savings:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.10) . '</span></div>';
        print '<div class="calc-row"><span class="label">Personal:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.05) . '</span></div>';
        print '<div class="calc-row"><span class="label">Giving:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.05) . '</span></div>';
        print '</div>';
    }
    print '</div>';

    # Envelope Method
    print '<div class="template-card">';
    print '<h3>' . $TEMPLATE_ENVELOPE{'name'} . '</h3>';
    print '<p>' . $TEMPLATE_ENVELOPE{'description'} . '</p>';
    print '<div>';
    print '<span class="template-tag tag-needs">Groceries</span>';
    print '<span class="template-tag tag-wants">Dining</span>';
    print '<span class="template-tag tag-info">Gas</span>';
    print '<span class="template-tag tag-savings">Clothing</span>';
    print '<span class="template-tag tag-wants">Entertainment</span>';
    print '</div>';
    print '<div style="margin-top:16px;font-size:0.85rem;color:var(--text-muted);">';
    print 'Allocate specific dollar amounts to each envelope based on your spending habits. ';
    print 'Use the Expense Manager to set your envelope amounts.</div>';
    print '</div>';

    # Pay Yourself First
    print '<div class="template-card">';
    print '<h3>' . $TEMPLATE_PAY_YOURSELF{'name'} . '</h3>';
    print '<p>' . $TEMPLATE_PAY_YOURSELF{'description'} . '</p>';
    print '<div>';
    print '<span class="template-tag tag-savings">Save 20%</span>';
    print '<span class="template-tag tag-info">Invest 10%</span>';
    print '<span class="template-tag tag-needs">Expenses 70%</span>';
    print '</div>';
    if ($total_income_stored > 0) {
        print '<div style="margin-top:16px;padding-top:16px;border-top:1px solid var(--border);">';
        print '<div class="calc-row"><span class="label">Save first:</span>';
        print '<span class="value" style="color:var(--success);">' . format_currency($total_income_stored * 0.20) . '</span></div>';
        print '<div class="calc-row"><span class="label">Invest:</span>';
        print '<span class="value" style="color:var(--info);">' . format_currency($total_income_stored * 0.10) . '</span></div>';
        print '<div class="calc-row"><span class="label">Living expenses:</span>';
        print '<span class="value">' . format_currency($total_income_stored * 0.70) . '</span></div>';
        print '</div>';
    }
    print '</div>';

    print '</div>';
}

# ---------- Calculator Page ----------

sub render_calculator_page {
    print '<div class="page-header">';
    print '<h1>Financial Calculators</h1>';
    print '<p>Plan smarter with built-in calculators for savings, debt, and budgeting</p>';
    print '</div>';

    # 50/30/20 Calculator
    print '<div class="card">';
    print '<div class="card-header"><h2>50/30/20 Budget Calculator</h2></div>';
    print '<div class="form-grid">';
    print '<div class="form-group"><label>Monthly Take-Home Income ($)</label>';
    $prefill_income = $total_income_stored || '';
    print "<input type=\"number\" id=\"rule_income\" step=\"0.01\" min=\"0\" value=\"$prefill_income\" placeholder=\"5000.00\">";
    print '</div></div>';
    print '<button class="btn btn-primary" onclick="calc503020()">Calculate</button>';
    print '<div id="rule_results" class="calc-result" style="display:none;">';
    print '<h3>Recommended Allocation</h3>';
    print '<div class="calc-row"><span class="label">Needs (50%)</span><span class="value" id="rule_needs" style="color:var(--danger);">$0.00</span></div>';
    print '<div class="calc-row"><span class="label">Wants (30%)</span><span class="value" id="rule_wants" style="color:var(--warning);">$0.00</span></div>';
    print '<div class="calc-row"><span class="label">Savings & Debt (20%)</span><span class="value" id="rule_savings" style="color:var(--success);">$0.00</span></div>';
    print '</div></div>';

    # Compound Interest Calculator
    print '<div class="card">';
    print '<div class="card-header"><h2>Compound Interest / Savings Growth Calculator</h2></div>';
    print '<div class="form-grid">';
    print '<div class="form-group"><label>Starting Amount ($)</label>';
    print '<input type="number" id="ci_principal" step="0.01" min="0" value="1000" placeholder="1000.00"></div>';
    print '<div class="form-group"><label>Annual Interest Rate (%)</label>';
    print '<input type="number" id="ci_rate" step="0.01" min="0" value="7" placeholder="7.0"></div>';
    print '<div class="form-group"><label>Years</label>';
    print '<input type="number" id="ci_years" step="1" min="1" value="10" placeholder="10"></div>';
    print '<div class="form-group"><label>Monthly Contribution ($)</label>';
    print '<input type="number" id="ci_monthly" step="0.01" min="0" value="200" placeholder="200.00"></div>';
    print '</div>';
    print '<button class="btn btn-primary" onclick="calcCompound()">Calculate Growth</button>';
    print '<div id="ci_results" class="calc-result" style="display:none;">';
    print '<h3>Projected Results</h3>';
    print '<div class="calc-row"><span class="label">Total Value</span><span class="value" id="ci_result_total" style="color:var(--success);">$0.00</span></div>';
    print '<div class="calc-row"><span class="label">Total Contributions</span><span class="value" id="ci_result_contrib">$0.00</span></div>';
    print '<div class="calc-row"><span class="label">Interest Earned</span><span class="value" id="ci_result_interest" style="color:var(--accent-light);">$0.00</span></div>';
    print '</div></div>';

    # Debt Payoff Calculator
    print '<div class="card">';
    print '<div class="card-header"><h2>Debt Payoff Calculator</h2></div>';
    print '<div class="form-grid">';
    print '<div class="form-group"><label>Current Balance ($)</label>';
    print '<input type="number" id="dp_balance" step="0.01" min="0" value="5000" placeholder="5000.00"></div>';
    print '<div class="form-group"><label>Interest Rate (APR %)</label>';
    print '<input type="number" id="dp_rate" step="0.01" min="0" value="18.99" placeholder="18.99"></div>';
    print '<div class="form-group"><label>Monthly Payment ($)</label>';
    print '<input type="number" id="dp_payment" step="0.01" min="0" value="200" placeholder="200.00"></div>';
    print '</div>';
    print '<button class="btn btn-primary" onclick="calcDebt()">Calculate Payoff</button>';
    print '<div id="dp_results" class="calc-result" style="display:none;">';
    print '<h3>Payoff Projection</h3>';
    print '<div class="calc-row"><span class="label">Time to Pay Off</span><span class="value" id="dp_result_months">-</span></div>';
    print '<div class="calc-row"><span class="label">Total Interest Paid</span><span class="value" id="dp_result_interest" style="color:var(--danger);">$0.00</span></div>';
    print '<div class="calc-row"><span class="label">Total Amount Paid</span><span class="value" id="dp_result_total">$0.00</span></div>';
    print '</div></div>';

    # Emergency Fund Calculator
    print '<div class="card">';
    print '<div class="card-header"><h2>Emergency Fund Calculator</h2></div>';
    print '<div class="form-grid">';
    $prefill_exp = $total_expenses_stored || '';
    print '<div class="form-group"><label>Monthly Expenses ($)</label>';
    print "<input type=\"number\" id=\"ef_expenses\" step=\"0.01\" min=\"0\" value=\"$prefill_exp\" placeholder=\"3000.00\"></div>";
    print '<div class="form-group"><label>Months of Coverage</label>';
    print '<input type="number" id="ef_months" step="1" min="1" value="6" placeholder="6"></div>';
    print '<div class="form-group"><label>Amount Already Saved ($)</label>';
    print '<input type="number" id="ef_saved" step="0.01" min="0" value="0" placeholder="0.00"></div>';
    print '</div>';
    print '<button class="btn btn-primary" onclick="calcEmergency()">Calculate</button>';
    print '<div id="ef_results" class="calc-result" style="display:none;">';
    print '<h3>Emergency Fund Status</h3>';
    print '<div class="calc-row"><span class="label">Target Fund Size</span><span class="value" id="ef_result_target" style="color:var(--info);">$0.00</span></div>';
    print '<div class="calc-row"><span class="label">Currently Saved</span><span class="value" id="ef_result_saved">$0.00</span></div>';
    print '<div class="calc-row"><span class="label">Still Needed</span><span class="value" id="ef_result_needed" style="color:var(--warning);">$0.00</span></div>';
    print '<div class="progress-container" style="margin-top:12px;">';
    print '<div class="progress-bar"><div id="ef_progress_fill" class="progress-fill" style="width:0%"></div></div>';
    print '<div class="progress-labels"><span id="ef_progress_pct">0%</span><span>Target</span></div>';
    print '</div></div></div>';
}

# ---------- Reports Page ----------

sub render_reports_page {
    print '<div class="page-header">';
    print '<h1>Budget Reports</h1>';
    print '<p>Detailed analysis and insights about your financial health</p>';
    print '</div>';

    if ($total_income_stored == 0 && $total_expenses_stored == 0) {
        print '<div class="alert alert-info">Enter your income and expenses first to generate reports.</div>';
        return;
    }

    # Spending Efficiency Score
    print '<div class="card">';
    print '<div class="card-header"><h2>Financial Health Score</h2></div>';

    $score = 100;
    @deductions = ();

    if ($total_income_stored > 0) {
        $spend_ratio = ($total_expenses_stored / $total_income_stored) * 100;
        if ($spend_ratio > 100) { $score -= 30; push @deductions, "Spending exceeds income (-30)"; }
        elsif ($spend_ratio > 90) { $score -= 20; push @deductions, "Spending over 90% of income (-20)"; }
        elsif ($spend_ratio > 80) { $score -= 10; push @deductions, "Spending over 80% of income (-10)"; }
    } else {
        $score -= 15; push @deductions, "No income entered (-15)";
    }

    if (scalar @stored_goals == 0) {
        $score -= 10; push @deductions, "No savings goals set (-10)";
    }

    $emergency_val = $stored_expenses{'Emergency Fund'} || 0;
    $retirement_val = $stored_expenses{'Retirement (401k/IRA)'} || 0;
    if ($emergency_val == 0 && $retirement_val == 0) {
        $score -= 15; push @deductions, "No emergency/retirement savings (-15)";
    }

    $savings_val = $stored_expenses{'Savings Contribution'} || 0;
    if ($total_income_stored > 0 && (($savings_val + $emergency_val + $retirement_val) / $total_income_stored) < 0.10) {
        $score -= 10; push @deductions, "Saving less than 10% of income (-10)";
    }

    if (scalar @stored_debts > 0) {
        $high_interest = 0;
        foreach $d (@stored_debts) {
            $high_interest++ if ($d->[2] || 0) > 20;
        }
        if ($high_interest > 0) {
            $score -= 10; push @deductions, "High-interest debt present (-10)";
        }
    }

    $score = 0 if $score < 0;
    $score_color = $score >= 80 ? 'success' : ($score >= 60 ? 'warning' : 'danger');

    print "<div style=\"text-align:center;padding:20px;\">";
    print "<div style=\"font-size:4rem;font-weight:900;color:var(--$score_color);\">$score</div>";
    print '<div style="font-size:1.1rem;color:var(--text-secondary);margin-bottom:16px;">out of 100</div>';
    print '<div class="progress-bar" style="max-width:400px;margin:0 auto;">';
    print "<div class=\"progress-fill $score_color\" style=\"width:${score}%\"></div>";
    print '</div></div>';

    if (scalar @deductions > 0) {
        print '<div style="margin-top:20px;">';
        print '<h3 style="font-size:0.9rem;color:var(--text-muted);margin-bottom:8px;">Score Breakdown:</h3>';
        foreach $ded (@deductions) {
            print "<div style=\"padding:6px 0;font-size:0.85rem;color:var(--text-secondary);\">- $ded</div>";
        }
        print '</div>';
    }
    print '</div>';

    # Top spending categories
    if ($total_expenses_stored > 0) {
        print '<div class="card">';
        print '<div class="card-header"><h2>Top Spending Categories</h2></div>';

        # Sort expenses by value
        @sorted_cats = sort { ($stored_expenses{$b} || 0) <=> ($stored_expenses{$a} || 0) } 
                       grep { !/^_/ && ($stored_expenses{$_} || 0) > 0 } keys %stored_expenses;

        $rank = 1;
        @medal_colors = ('#ffd700','#c0c0c0','#cd7f32');
        foreach $cat (@sorted_cats) {
            last if $rank > 10;
            $val = $stored_expenses{$cat};
            $pct = calc_percentage($val, $total_expenses_stored);
            $medal_color = $rank <= 3 ? $medal_colors[$rank-1] : 'var(--text-muted)';

            print '<div style="display:flex;align-items:center;gap:16px;padding:10px 0;border-bottom:1px solid var(--border);">';
            print "<div style=\"width:32px;height:32px;border-radius:50%;background:${medal_color};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:0.85rem;color:var(--bg-primary);\">$rank</div>";
            print "<div style=\"flex:1;\"><div style=\"font-weight:600;\">$cat</div>";
            print "<div style=\"font-size:0.8rem;color:var(--text-muted);\">${pct}% of expenses</div></div>";
            print '<div style="font-weight:700;font-variant-numeric:tabular-nums;">' . format_currency($val) . '</div>';
            print '</div>';
            $rank++;
        }
        print '</div>';
    }

    # Income vs Expenses comparison
    if ($total_income_stored > 0 && $total_expenses_stored > 0) {
        print '<div class="card">';
        print '<div class="card-header"><h2>Monthly Projections</h2></div>';
        print '<table class="data-table">';
        print '<tr><th>Metric</th><th>Monthly</th><th>Quarterly</th><th>Annual</th></tr>';
        print '<tr><td>Income</td>';
        print '<td class="amount positive">' . format_currency($total_income_stored) . '</td>';
        print '<td class="amount positive">' . format_currency($total_income_stored * 3) . '</td>';
        print '<td class="amount positive">' . format_currency($total_income_stored * 12) . '</td></tr>';
        print '<tr><td>Expenses</td>';
        print '<td class="amount negative">' . format_currency($total_expenses_stored) . '</td>';
        print '<td class="amount negative">' . format_currency($total_expenses_stored * 3) . '</td>';
        print '<td class="amount negative">' . format_currency($total_expenses_stored * 12) . '</td></tr>';
        print '<tr style="font-weight:700;"><td>Net Savings</td>';
        print '<td class="amount ' . ($net_balance >= 0 ? 'positive' : 'negative') . '">' . format_currency($net_balance) . '</td>';
        print '<td class="amount ' . ($net_balance >= 0 ? 'positive' : 'negative') . '">' . format_currency($net_balance * 3) . '</td>';
        print '<td class="amount ' . ($net_balance >= 0 ? 'positive' : 'negative') . '">' . format_currency($net_balance * 12) . '</td></tr>';
        print '</table></div>';
    }
}

# ---------- Export Page ----------

sub render_export_page {
    print '<div class="page-header">';
    print '<h1>Export &amp; Print</h1>';
    print '<p>Print your budget or view a printer-friendly summary</p>';
    print '</div>';

    print '<div class="card">';
    print '<div class="card-header"><h2>Print Budget</h2></div>';
    print '<p style="margin-bottom:16px;color:var(--text-secondary);">Click below to open your browser\'s print dialog. The sidebar and forms will be hidden automatically.</p>';
    print '<button class="btn btn-primary" onclick="printBudget()">Print / Save as PDF</button>';
    print '</div>';

    # Printable summary
    print '<div class="card">';
    print '<div class="card-header"><h2>Budget Summary for Export</h2></div>';

    print '<h3 style="margin-bottom:12px;">Income</h3>';
    print '<table class="data-table">';
    print '<tr><th>Source</th><th>Amount</th></tr>';
    foreach $cat (@INCOME_CATEGORIES) {
        $val = $stored_income{$cat} || 0;
        next unless $val > 0;
        print "<tr><td>$cat</td><td class=\"amount positive\">" . format_currency($val) . "</td></tr>";
    }
    print '<tr style="font-weight:700;"><td>Total Income</td><td class="amount positive">' . format_currency($total_income_stored) . '</td></tr>';
    print '</table>';

    print '<h3 style="margin:20px 0 12px;">Expenses</h3>';
    print '<table class="data-table">';
    print '<tr><th>Category</th><th>Amount</th></tr>';
    foreach $cat (@EXPENSE_CATEGORIES) {
        $val = $stored_expenses{$cat} || 0;
        next unless $val > 0;
        print "<tr><td>$cat</td><td class=\"amount negative\">" . format_currency($val) . "</td></tr>";
    }
    print '<tr style="font-weight:700;"><td>Total Expenses</td><td class="amount negative">' . format_currency($total_expenses_stored) . '</td></tr>';
    print '</table>';

    print '<div style="margin-top:24px;padding:16px;background:var(--bg-secondary);border-radius:8px;">';
    print '<div style="display:flex;justify-content:space-between;font-size:1.2rem;font-weight:700;">';
    print '<span>Net Balance:</span>';
    $nb_color = $net_balance >= 0 ? 'var(--success)' : 'var(--danger)';
    print "<span style=\"color:$nb_color;\">" . format_currency($net_balance) . '</span>';
    print '</div></div>';
    print '</div>';
}
