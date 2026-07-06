#Requires -Version 7.4
# Subtle, purposeful motion for the GUI. Every animation is gated on $script:Animate so reduced-motion
# is honored (Windows "Show animations in Windows" off -> SystemParameters.ClientAreaAnimation = false).
# Animate transform + opacity only, never layout. 120-220ms, ease-out. See ~/.claude/design-playbook.md.

$script:Animate = $true
try { $script:Animate = [System.Windows.SystemParameters]::ClientAreaAnimation } catch { $script:Animate = $true }

function New-OGDouble([double]$from, [double]$to, [int]$ms) {
    $d = New-Object System.Windows.Media.Animation.DoubleAnimation($from, $to, (New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds($ms))))
    $e = New-Object System.Windows.Media.Animation.CubicEase
    $e.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $d.EasingFunction = $e
    $d
}

# Fade + small upward slide — used when a view becomes visible.
function Invoke-ViewIn($view) {
    if (-not $script:Animate -or -not $view) { return }
    $tt = New-Object System.Windows.Media.TranslateTransform
    $view.RenderTransform = $tt
    $view.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-OGDouble 0 1 170))
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-OGDouble 10 0 200))
}

# Fade + small upward slide for any element (e.g. a results grid appearing).
function Invoke-FadeIn($element, [double]$fromY = 6) {
    if (-not $script:Animate -or -not $element) { return }
    $tt = New-Object System.Windows.Media.TranslateTransform
    $element.RenderTransform = $tt
    $element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-OGDouble 0 1 180))
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, (New-OGDouble $fromY 0 200))
}

# Slide in from the right + fade — used for toasts.
function Invoke-SlideIn($element, [double]$fromX = 40) {
    if (-not $script:Animate -or -not $element) { return }
    $tt = New-Object System.Windows.Media.TranslateTransform
    $element.RenderTransform = $tt
    $element.BeginAnimation([System.Windows.UIElement]::OpacityProperty, (New-OGDouble 0 1 200))
    $tt.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, (New-OGDouble $fromX 0 220))
}

# Animated count-up for a numeric TextBlock (dashboard KPIs). Eased; honors reduced-motion.
function Start-CountUp($textBlock, [double]$to, [int]$ms = 650, [string]$format = '{0:N0}') {
    if (-not $textBlock) { return }
    if (-not $script:Animate -or $to -le 0) { $textBlock.Text = ($format -f $to); return }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(20)
    $timer.Tag = @{ TB = $textBlock; To = [double]$to; Ms = $ms; Start = [DateTime]::UtcNow; Fmt = $format }
    $timer.Add_Tick({
        $t = $args[0]; $st = $t.Tag
        $p = [Math]::Min(1.0, ([DateTime]::UtcNow - $st.Start).TotalMilliseconds / $st.Ms)
        $eased = 1 - [Math]::Pow(1 - $p, 3)
        $st.TB.Text = ($st.Fmt -f ($st.To * $eased))
        if ($p -ge 1.0) { $st.TB.Text = ($st.Fmt -f $st.To); $t.Stop() }
    })
    $timer.Start()
}
