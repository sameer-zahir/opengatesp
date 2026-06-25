#Requires -Version 7.4
<#
.SYNOPSIS
    Windows GUI for OpenGateSP — a simple ShareGate-style front end over the engine.
.DESCRIPTION
    Loads the OpenGateSP module into a dedicated background runspace (so the PnP connection
    persists and the UI never freezes during long operations) and drives it from a WPF
    window: Connect, Reports, Migrate, Provision. Results render in a grid and export to
    CSV/HTML. Windows-only (WPF).
.EXAMPLE
    pwsh -STA -File ./gui/Start-OpenGateSPGui.ps1
#>
[CmdletBinding()]
param(
    [string]$ModulePath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ModulePath) { $ModulePath = Join-Path (Split-Path $here -Parent) 'module\OpenGateSP\OpenGateSP.psd1' }
if (-not (Test-Path -LiteralPath $ModulePath)) { throw "OpenGateSP module not found at $ModulePath" }

# Scheduled-task command builder, shared with scripts/ and tests/ (pure, UI-thread safe).
$schedHelper = Join-Path (Split-Path $here -Parent) 'scripts\scheduled\Get-SPScheduledCommand.ps1'
if (Test-Path -LiteralPath $schedHelper) { . $schedHelper }

# --- background worker runspace: holds the module + PnP connection ----------------------
$script:Worker = [runspacefactory]::CreateRunspace()
$script:Worker.ApartmentState = 'STA'
$script:Worker.ThreadOptions  = 'ReuseThread'
$script:Worker.Open()
$boot = [powershell]::Create()
$boot.Runspace = $script:Worker
$null = $boot.AddScript("Import-Module '$ModulePath' -Force -ErrorAction Stop").Invoke()
$boot.Dispose()
$script:Busy       = $false
$script:LastReport = @()

# --- load the window --------------------------------------------------------------------
[xml]$xamlDoc = Get-Content -LiteralPath (Join-Path $here 'MainWindow.xaml') -Raw
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlDoc))

# Bind every x:Name to a $script:<Name> variable for easy access in handlers.
$xamlDoc.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    $n = $_.Attributes['x:Name'].Value
    if ($n) { Set-Variable -Name $n -Value $window.FindName($n) -Scope script }
}

# --- theming: Squintless control templates + light/dark, inline so the GUI ships in one file ---
$script:GuiCfgPath = Join-Path $env:APPDATA 'OpenGateSP\gui.json'

$script:XamlControls = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Style x:Key="Muted" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
        <Setter Property="FontSize" Value="12.5"/>
    </Style>
    <Style x:Key="Section" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="Button">
        <Setter Property="Foreground" Value="{DynamicResource AccentFg}"/>
        <Setter Property="Background" Value="{DynamicResource Accent}"/>
        <Setter Property="BorderBrush" Value="Transparent"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Padding" Value="15,8"/>
        <Setter Property="Margin" Value="0,8,8,8"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="SnapsToDevicePixels" Value="True"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border CornerRadius="9" Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" SnapsToDevicePixels="True">
                        <Grid>
                            <Border x:Name="ov" CornerRadius="9" Background="#FFFFFFFF" Opacity="0"/>
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ov" Property="Opacity" Value="0.10"/></Trigger>
                        <Trigger Property="IsPressed" Value="True"><Setter TargetName="ov" Property="Opacity" Value="0.18"/></Trigger>
                        <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style x:Key="GhostButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource BorderStrong}"/>
        <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="GoodButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="{DynamicResource Good}"/>
        <Setter Property="Foreground" Value="{DynamicResource GoodFg}"/>
    </Style>
    <Style x:Key="WarnButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="{DynamicResource Warn}"/>
        <Setter Property="Foreground" Value="{DynamicResource AccentFg}"/>
    </Style>
    <Style x:Key="ThemeToggle" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="16"/>
        <Setter Property="Padding" Value="8,4"/>
        <Setter Property="Margin" Value="0"/>
    </Style>
    <Style TargetType="TextBox">
        <Setter Property="Background" Value="{DynamicResource BgElev}"/>
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="CaretBrush" Value="{DynamicResource Fg}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="9,7"/>
        <Setter Property="Margin" Value="0,5"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="TextBox">
                    <Border x:Name="bd" CornerRadius="8" Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                        <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource BorderStrong}"/></Trigger>
                        <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="CheckBox">
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="Margin" Value="0,6,18,6"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="CheckBox">
                    <StackPanel Orientation="Horizontal" Background="Transparent">
                        <Border x:Name="box" Width="18" Height="18" CornerRadius="5" VerticalAlignment="Center"
                                Background="{DynamicResource BgElev}" BorderBrush="{DynamicResource BorderStrong}" BorderThickness="1.4">
                            <Path x:Name="check" Width="11" Height="11" Stretch="Uniform" Visibility="Collapsed"
                                  Data="M0,5 L4,9 L11,0" Stroke="{DynamicResource AccentFg}" StrokeThickness="2"
                                  HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ContentPresenter Margin="9,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="box" Property="Background" Value="{DynamicResource Accent}"/>
                            <Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                            <Setter TargetName="check" Property="Visibility" Value="Visible"/>
                        </Trigger>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="ComboBox">
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="Background" Value="{DynamicResource BgElev}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
        <Setter Property="Height" Value="36"/>
        <Setter Property="Margin" Value="0,5"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ComboBox">
                    <Grid>
                        <ToggleButton Focusable="False" ClickMode="Press"
                                      IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                            <ToggleButton.Template>
                                <ControlTemplate TargetType="ToggleButton">
                                    <Border x:Name="tb" CornerRadius="8" Background="{DynamicResource BgElev}"
                                            BorderBrush="{DynamicResource Border}" BorderThickness="1">
                                        <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"
                                              Data="M0,0 L4,4 L8,0" Stroke="{DynamicResource FgMute}" StrokeThickness="1.6"/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="tb" Property="BorderBrush" Value="{DynamicResource BorderStrong}"/></Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </ToggleButton.Template>
                        </ToggleButton>
                        <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" Margin="12,0,32,0"
                                          VerticalAlignment="Center" HorizontalAlignment="Left" IsHitTestVisible="False"/>
                        <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" PopupAnimation="Fade" Focusable="False">
                            <Border Background="{DynamicResource BgElev}" BorderBrush="{DynamicResource BorderStrong}" BorderThickness="1" CornerRadius="8" Margin="0,4,0,0"
                                    MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                                <ScrollViewer MaxHeight="260"><StackPanel IsItemsHost="True" Margin="4"/></ScrollViewer>
                            </Border>
                        </Popup>
                    </Grid>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="Padding" Value="10,7"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ComboBoxItem">
                    <Border x:Name="ib" CornerRadius="6" Background="Transparent" Padding="{TemplateBinding Padding}">
                        <ContentPresenter/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ib" Property="Background" Value="{DynamicResource BgElev2}"/></Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="TabControl">
        <Setter Property="Background" Value="{DynamicResource Bg}"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="TabControl">
                    <DockPanel>
                        <Border DockPanel.Dock="Top" Background="{DynamicResource BgElev}" BorderBrush="{DynamicResource Border}" BorderThickness="0,0,0,1">
                            <TabPanel IsItemsHost="True" Margin="10,0"/>
                        </Border>
                        <Border Background="{DynamicResource Bg}"><ContentPresenter ContentSource="SelectedContent"/></Border>
                    </DockPanel>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="TabItem">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="TabItem">
                    <Grid Background="Transparent">
                        <Border Padding="18,12">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <Border x:Name="ul" Height="2" Margin="14,0" VerticalAlignment="Bottom" CornerRadius="1" Background="{DynamicResource Accent}" Visibility="Collapsed"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{DynamicResource Fg}"/></Trigger>
                        <Trigger Property="IsSelected" Value="True">
                            <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
                            <Setter TargetName="ul" Property="Visibility" Value="Visible"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style TargetType="DataGrid">
        <Setter Property="Background" Value="{DynamicResource Bg}"/>
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="RowBackground" Value="{DynamicResource Bg}"/>
        <Setter Property="AlternatingRowBackground" Value="{DynamicResource BgElev}"/>
        <Setter Property="GridLinesVisibility" Value="Horizontal"/>
        <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource Border}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="HeadersVisibility" Value="Column"/>
        <Setter Property="IsReadOnly" Value="True"/>
        <Setter Property="AutoGenerateColumns" Value="True"/>
        <Setter Property="CanUserResizeRows" Value="False"/>
        <Setter Property="RowHeight" Value="30"/>
        <Setter Property="ColumnHeaderHeight" Value="36"/>
        <Setter Property="FontSize" Value="12.5"/>
        <Setter Property="SelectionUnit" Value="FullRow"/>
    </Style>
    <Style TargetType="DataGridColumnHeader">
        <Setter Property="Background" Value="{DynamicResource BgElev}"/>
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Padding" Value="11,7"/>
        <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
        <Setter Property="BorderThickness" Value="0,0,1,1"/>
        <Setter Property="HorizontalContentAlignment" Value="Left"/>
    </Style>
    <Style TargetType="DataGridRow">
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource BgElev2}"/></Trigger>
        </Style.Triggers>
    </Style>
    <Style TargetType="DataGridCell">
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Padding" Value="11,6"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="DataGridCell">
                    <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}"><ContentPresenter VerticalAlignment="Center"/></Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsSelected" Value="True">
                            <Setter Property="Background" Value="{DynamicResource BgElev2}"/>
                            <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
        <Style.Triggers>
            <DataTrigger Binding="{Binding Severity}" Value="Error"><Setter Property="Foreground" Value="{DynamicResource Danger}"/></DataTrigger>
            <DataTrigger Binding="{Binding Severity}" Value="Warning"><Setter Property="Foreground" Value="{DynamicResource Warn}"/></DataTrigger>
        </Style.Triggers>
    </Style>

    <!-- Sidebar nav -->
    <Style x:Key="NavGroupHeader" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgFaint}"/>
        <Setter Property="FontSize" Value="10.5"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Margin" Value="14,2,0,6"/>
    </Style>
    <Style x:Key="NavButton" TargetType="RadioButton">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="13.5"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Margin" Value="0,1"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="RadioButton">
                    <Grid>
                        <Border x:Name="bg" CornerRadius="8" Background="Transparent"/>
                        <Border x:Name="bar" Width="3" HorizontalAlignment="Left" CornerRadius="2" Margin="0,7"
                                Background="{DynamicResource Accent}" Visibility="Collapsed"/>
                        <ContentPresenter Margin="16,9" VerticalAlignment="Center"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="bg" Property="Background" Value="{DynamicResource BgElev2}"/>
                            <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
                        </Trigger>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="bg" Property="Background" Value="{DynamicResource BgElev2}"/>
                            <Setter TargetName="bar" Property="Visibility" Value="Visible"/>
                            <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- Home cards -->
    <Style x:Key="Card" TargetType="Button">
        <Setter Property="Background" Value="{DynamicResource BgElev}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource Border}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Height" Value="150"/>
        <Setter Property="Margin" Value="0,0,16,16"/>
        <Setter Property="HorizontalContentAlignment" Value="Left"/>
        <Setter Property="VerticalContentAlignment" Value="Top"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="cb" CornerRadius="14" Padding="18,16"
                            Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                        <ContentPresenter VerticalAlignment="Top" HorizontalAlignment="Left"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="cb" Property="Background" Value="{DynamicResource BgElev2}"/>
                            <Setter TargetName="cb" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style x:Key="CardTitle" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource Fg}"/>
        <Setter Property="FontSize" Value="15.5"/>
        <Setter Property="FontWeight" Value="Bold"/>
    </Style>
    <Style x:Key="CardBody" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="12.5"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
        <Setter Property="Margin" Value="0,8,0,0"/>
    </Style>
    <Style x:Key="CardMeta" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgFaint}"/>
        <Setter Property="FontFamily" Value="Consolas"/>
        <Setter Property="FontSize" Value="11.5"/>
        <Setter Property="Margin" Value="0,12,0,0"/>
    </Style>
    <Style x:Key="Breadcrumb" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="13.5"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="EmptyState" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgFaint}"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="HorizontalAlignment" Value="Center"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
        <Setter Property="MaxWidth" Value="380"/>
        <Setter Property="TextAlignment" Value="Center"/>
    </Style>
</ResourceDictionary>
'@

$script:XamlDark = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <SolidColorBrush x:Key="Bg" Color="#222436"/>
    <SolidColorBrush x:Key="BgElev" Color="#2A2E44"/>
    <SolidColorBrush x:Key="BgElev2" Color="#2F334D"/>
    <SolidColorBrush x:Key="Fg" Color="#C8D3F5"/>
    <SolidColorBrush x:Key="FgMute" Color="#828BB8"/>
    <SolidColorBrush x:Key="FgFaint" Color="#636DA6"/>
    <SolidColorBrush x:Key="Accent" Color="#82AAFF"/>
    <SolidColorBrush x:Key="AccentHover" Color="#A2BFFF"/>
    <SolidColorBrush x:Key="AccentFg" Color="#1B1D2B"/>
    <SolidColorBrush x:Key="Border" Color="#353A57"/>
    <SolidColorBrush x:Key="BorderStrong" Color="#444A73"/>
    <SolidColorBrush x:Key="Good" Color="#C3E88D"/>
    <SolidColorBrush x:Key="GoodFg" Color="#1B1D2B"/>
    <SolidColorBrush x:Key="Warn" Color="#FFC777"/>
    <SolidColorBrush x:Key="Danger" Color="#FF757F"/>
</ResourceDictionary>
'@

$script:XamlLight = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <SolidColorBrush x:Key="Bg" Color="#FBF1C7"/>
    <SolidColorBrush x:Key="BgElev" Color="#F2E5BC"/>
    <SolidColorBrush x:Key="BgElev2" Color="#EBDBB2"/>
    <SolidColorBrush x:Key="Fg" Color="#3C3836"/>
    <SolidColorBrush x:Key="FgMute" Color="#665C54"/>
    <SolidColorBrush x:Key="FgFaint" Color="#A89984"/>
    <SolidColorBrush x:Key="Accent" Color="#D65D0E"/>
    <SolidColorBrush x:Key="AccentHover" Color="#AF3A03"/>
    <SolidColorBrush x:Key="AccentFg" Color="#FFF8E8"/>
    <SolidColorBrush x:Key="Border" Color="#E6D9AD"/>
    <SolidColorBrush x:Key="BorderStrong" Color="#D5C4A1"/>
    <SolidColorBrush x:Key="Good" Color="#427B58"/>
    <SolidColorBrush x:Key="GoodFg" Color="#FFF8E8"/>
    <SolidColorBrush x:Key="Warn" Color="#B57614"/>
    <SolidColorBrush x:Key="Danger" Color="#9D0006"/>
</ResourceDictionary>
'@

function Read-Dict([string]$xaml) { [Windows.Markup.XamlReader]::Parse($xaml) }
function Get-GuiTheme {
    if (Test-Path -LiteralPath $script:GuiCfgPath) {
        try { $t = (Get-Content -LiteralPath $script:GuiCfgPath -Raw | ConvertFrom-Json).Theme; if ($t) { return $t } } catch { }
    }
    'Dark'
}
function Save-GuiTheme([string]$name) {
    $dir = Split-Path $script:GuiCfgPath -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    @{ Theme = $name } | ConvertTo-Json | Set-Content -LiteralPath $script:GuiCfgPath -Encoding utf8
}

$script:Controls = Read-Dict $script:XamlControls
$window.Resources.MergedDictionaries.Add($script:Controls)
$script:ThemeDict = $null

function Set-Theme([string]$name) {
    $xaml = if ($name -eq 'Light') { $script:XamlLight } else { $script:XamlDark }
    $td = Read-Dict $xaml
    $md = $window.Resources.MergedDictionaries
    if ($script:ThemeDict) { [void]$md.Remove($script:ThemeDict) }
    $md.Insert(0, $td)
    $script:ThemeDict    = $td
    $script:CurrentTheme = $name
    $script:BtnTheme.Content = if ($name -eq 'Dark') { [char]0x2600 } else { [char]0x263E }
    Save-GuiTheme $name
}

Set-Theme (Get-GuiTheme)
$script:BtnTheme.Add_Click({ Set-Theme $(if ($script:CurrentTheme -eq 'Dark') { 'Light' } else { 'Dark' }) })

# --- helpers ----------------------------------------------------------------------------
function Set-Status([string]$text) { $script:StatusText.Text = $text }

function Show-Grid($grid, $data, $empty) {
    $arr = @($data)
    $grid.ItemsSource = $null
    if ($arr.Count -gt 0) { $grid.ItemsSource = $arr }
    if ($empty) {
        $empty.Visibility = if ($arr.Count -gt 0) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    }
    $arr
}

function Confirm-Action([string]$message) {
    [System.Windows.MessageBox]::Show($message, 'Confirm', 'YesNo', 'Warning') -eq [System.Windows.MessageBoxResult]::Yes
}

function Select-FolderPath {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dlg.SelectedPath }
}

function Select-FilePath([string]$filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*') {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = $filter
    if ($dlg.ShowDialog()) { $dlg.FileName }
}

function Save-FilePath([string]$filter, [string]$default) {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = $filter; $dlg.FileName = $default
    if ($dlg.ShowDialog()) { $dlg.FileName }
}

# Run a module command in the worker runspace; marshal the result back on the UI thread.
function Invoke-Worker {
    param(
        [Parameter(Mandatory)][string]$Command,
        [hashtable]$Parameters,
        [Parameter(Mandatory)][scriptblock]$OnDone
    )
    if ($script:Busy) { Set-Status 'Busy — wait for the current operation to finish.'; return }
    $script:Busy = $true
    if ($script:BusyBar) { $script:BusyBar.Visibility = [System.Windows.Visibility]::Visible }
    Set-Status "Running $Command ..."

    $ps = [powershell]::Create()
    $ps.Runspace = $script:Worker
    $null = $ps.AddCommand($Command)
    if ($Parameters) { $null = $ps.AddParameters($Parameters) }
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    # Carry state on .Tag so the Tick handler needs no captured variables.
    $timer.Tag = @{ Ps = $ps; Handle = $handle; OnDone = $OnDone; Command = $Command }
    $timer.Add_Tick({
        $tmr = $args[0]
        $st  = $tmr.Tag
        if (-not $st.Handle.IsCompleted) { return }
        $tmr.Stop()

        $result = $null; $err = $null
        try { $result = $st.Ps.EndInvoke($st.Handle) }
        catch { $err = $_.Exception.Message }
        if (-not $err -and $st.Ps.Streams.Error.Count -gt 0) {
            $err = ($st.Ps.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n"
        }
        $st.Ps.Dispose()
        $script:Busy = $false
        if ($script:BusyBar) { $script:BusyBar.Visibility = [System.Windows.Visibility]::Collapsed }
        & $st.OnDone $result $err
    })
    $timer.Start()
}

# --- prefill connection fields from saved config ----------------------------------------
$cfgPath = Join-Path $env:APPDATA 'OpenGateSP\spconfig.json'
if (Test-Path -LiteralPath $cfgPath) {
    try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
        if ($cfg.Url)      { $script:TbUrl.Text      = $cfg.Url }
        if ($cfg.ClientId) { $script:TbClientId.Text = $cfg.ClientId }
        if ($cfg.Tenant)   { $script:TbTenant.Text   = $cfg.Tenant }
    } catch { }
}

# --- Connect ----------------------------------------------------------------------------
$script:BtnConnect.Add_Click({
    $p = @{ ClientId = $script:TbClientId.Text.Trim(); SaveConfig = $true }
    if ($script:TbTenant.Text.Trim()) { $p.Tenant = $script:TbTenant.Text.Trim() }
    if ($script:TbUrl.Text.Trim())    { $p.Url    = $script:TbUrl.Text.Trim() }
    if ($script:CbAdmin.IsChecked)    { $p.Admin       = $true }
    if ($script:CbDevice.IsChecked)   { $p.DeviceLogin = $true }
    if (-not $p.ClientId) { Set-Status 'Client ID is required (see docs/02).'; return }

    $script:ConnStatus.Text = 'Connecting...'
    Invoke-Worker -Command 'Connect-SPTool' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) {
            $script:ConnStatus.Text = 'Not connected'
            $script:ConnDot.Fill = $window.FindResource('Danger')
            Set-Status "Connect failed: $err"
        } else {
            $r = @($result)[0]
            $script:ConnStatus.Text = "Connected: $($r.Url)"
            $script:ConnDot.Fill = $window.FindResource('Good')
            Set-Status 'Connected.'
        }
    }
})

# --- Reports ----------------------------------------------------------------------------
$script:BtnRunReport.Add_Click({
    $site = $script:TbReportSite.Text.Trim()
    $incl = [bool]$script:CbInclLists.IsChecked
    switch ($script:CbReport.SelectedIndex) {
        0 { $cmd = 'Get-SPSharingReport';    $p = @{ SiteUrl = $site; IncludeLinks = $incl } }
        1 { $cmd = 'Get-SPPermissionReport'; $p = @{ SiteUrl = $site; IncludeListPermissions = $incl } }
        2 { $cmd = 'Get-SPSiteInventory';    $p = @{ IncludeStorage = $true } }
        default { return }
    }
    if ($cmd -ne 'Get-SPSiteInventory' -and -not $site) { Set-Status 'Enter a Site URL for this report.'; return }

    Invoke-Worker -Command $cmd -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Report failed: $err"; return }
        $script:LastReport = Show-Grid $script:GridReport $result $script:EmptyReport
        Set-Status "$($script:LastReport.Count) row(s)."
    }
})

$script:BtnExportCsv.Add_Click({
    if (-not $script:LastReport.Count) { Set-Status 'Nothing to export — run a report first.'; return }
    $path = Save-FilePath 'CSV (*.csv)|*.csv' 'report.csv'
    if ($path) { $script:LastReport | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8; Set-Status "Saved $path" }
})

$script:BtnExportHtml.Add_Click({
    if (-not $script:LastReport.Count) { Set-Status 'Nothing to export — run a report first.'; return }
    $path = Save-FilePath 'HTML (*.html)|*.html' 'report.html'
    if ($path) {
        $style = '<style>body{font-family:Segoe UI,Arial;background:#1b1d2b;color:#c0caf5}table{border-collapse:collapse;width:100%}th,td{border:1px solid #3b4261;padding:6px 10px;text-align:left}th{background:#24283b;color:#7aa2f7}</style>'
        $script:LastReport | ConvertTo-Html -Head $style | Out-File -LiteralPath $path -Encoding utf8
        Set-Status "Saved $path"
    }
})

# --- Migrate ----------------------------------------------------------------------------
$script:BtnBrowseSource.Add_Click({ $f = Select-FolderPath; if ($f) { $script:TbSource.Text = $f } })

function Invoke-Migration([bool]$Preview) {
    $src  = $script:TbSource.Text.Trim()
    $site = $script:TbMigSite.Text.Trim()
    if (-not $src -or -not $site) { Set-Status 'Source folder and Site URL are required.'; return }

    $p = @{
        Source             = $src
        SiteUrl            = $site
        Library            = ($script:TbLibrary.Text.Trim()) ? $script:TbLibrary.Text.Trim() : 'Documents'
        TargetFolder       = $script:TbTargetFolder.Text.Trim()
        PreserveTimestamps = [bool]$script:CbPreserve.IsChecked
        Overwrite          = [bool]$script:CbOverwrite.IsChecked
    }
    if ($Preview) { $p.WhatIf = $true }
    else {
        if (-not (Confirm-Action "Upload files from `n$src`nto $site ?")) { Set-Status 'Cancelled.'; return }
        $p.Force = $true   # GUI confirmed; skip the engine's console prompt
    }

    Invoke-Worker -Command 'Start-SPFileMigration' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Migration failed: $err"; return }
        $rows = Show-Grid $script:GridMig $result $script:EmptyMig
        Set-Status "$($rows.Count) file row(s). See ./logs for the full transcript."
    }
}
$script:BtnPreviewMig.Add_Click({ Invoke-Migration $true })
$script:BtnRunMig.Add_Click({ Invoke-Migration $false })

# --- Provision --------------------------------------------------------------------------
$script:BtnCreateSite.Add_Click({
    $title = $script:TbSiteTitle.Text.Trim()
    $alias = $script:TbSiteAlias.Text.Trim()
    $type  = @('TeamSite', 'CommunicationSite')[$script:CbSiteType.SelectedIndex]
    if (-not $title -or -not $alias) { Set-Status 'Title and Alias/URL are required.'; return }
    if (-not (Confirm-Action "Create $type '$title' ($alias)?")) { Set-Status 'Cancelled.'; return }

    $p = @{ Title = $title; Type = $type }
    if ($type -eq 'TeamSite') { $p.Alias = $alias } else { $p.Url = $alias }
    if ($script:TbTemplatePath.Text.Trim()) { $p.TemplatePath = $script:TbTemplatePath.Text.Trim() }
    $libs = $script:TbLibraries.Text.Trim()
    if ($libs) { $p.Libraries = @($libs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

    Invoke-Worker -Command 'New-SPSiteFromTemplate' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Create failed: $err"; return }
        Show-Grid $script:GridProvision $result $script:EmptyProvision | Out-Null
        Set-Status 'Site request submitted.'
    }
})

$script:BtnBrowseCsv.Add_Click({ $f = Select-FilePath; if ($f) { $script:TbBulkCsv.Text = $f } })

function Invoke-Bulk([bool]$Preview) {
    $site = $script:TbBulkSite.Text.Trim()
    $list = $script:TbBulkList.Text.Trim()
    $csv  = $script:TbBulkCsv.Text.Trim()
    if (-not $site -or -not $list -or -not $csv) { Set-Status 'Site, List and CSV are required.'; return }

    $p = @{ SiteUrl = $site; List = $list; CsvPath = $csv }
    if ($Preview) { $p.WhatIf = $true }
    else {
        if (-not (Confirm-Action "Apply metadata from`n$csv`nto '$list' on $site ?")) { Set-Status 'Cancelled.'; return }
        $p.Force = $true
    }

    Invoke-Worker -Command 'Set-SPBulkMetadata' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Bulk update failed: $err"; return }
        $rows = Show-Grid $script:GridProvision $result $script:EmptyProvision
        Set-Status "$($rows.Count) item row(s)."
    }
}
$script:BtnPreviewBulk.Add_Click({ Invoke-Bulk $true })
$script:BtnRunBulk.Add_Click({ Invoke-Bulk $false })

# --- Provision: template picker ---------------------------------------------------------
$script:BtnBrowseTemplate.Add_Click({ $f = Select-FilePath 'PnP templates (*.xml;*.pnp)|*.xml;*.pnp|All files (*.*)|*.*'; if ($f) { $script:TbTemplatePath.Text = $f } })

# --- Pre-check --------------------------------------------------------------------------
$script:BtnBrowsePreSource.Add_Click({ $f = Select-FolderPath; if ($f) { $script:TbPreSource.Text = $f } })
$script:BtnRunPrecheck.Add_Click({
    $src = $script:TbPreSource.Text.Trim()
    if (-not $src) { Set-Status 'Choose a source folder to pre-check.'; return }
    $p = @{ Source = $src }
    if ($script:TbPreSite.Text.Trim())    { $p.SiteUrl = $script:TbPreSite.Text.Trim() }
    if ($script:TbPreLibrary.Text.Trim()) { $p.Library = $script:TbPreLibrary.Text.Trim() }
    $mp = 0
    if ([int]::TryParse($script:TbPreMaxPath.Text.Trim(), [ref]$mp) -and $mp -gt 0) { $p.MaxPathLength = $mp }

    Invoke-Worker -Command 'Test-SPMigrationReadiness' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Pre-check failed: $err"; return }
        $rows = @(Show-Grid $script:GridPrecheck $result $script:EmptyPrecheck)
        if ($rows.Count) {
            $e = @($rows | Where-Object Severity -eq 'Error').Count
            $w = @($rows | Where-Object Severity -eq 'Warning').Count
            Set-Status "$($rows.Count) issue(s): $e error(s), $w warning(s)."
        }
        else {
            $script:EmptyPrecheck.Text = 'No blockers found — this source is clear to migrate.'
            Set-Status 'No blockers found — clear to migrate.'
        }
    }
})

# --- Scheduled reports ------------------------------------------------------------------
function Get-SchedParams {
    $reports = @()
    if ($script:CbSchedSharing.IsChecked) { $reports += 'Sharing' }
    if ($script:CbSchedPerms.IsChecked) { $reports += 'Permissions' }
    $p = @{ SiteUrl = $script:TbSchedSite.Text.Trim(); Reports = $reports }
    if ($script:TbSchedOut.Text.Trim())   { $p.OutDir = $script:TbSchedOut.Text.Trim() }
    if ($script:TbSchedThumb.Text.Trim()) { $p.Thumbprint = $script:TbSchedThumb.Text.Trim() }
    if ($script:TbClientId.Text.Trim())   { $p.ClientId = $script:TbClientId.Text.Trim() }
    if ($script:TbTenant.Text.Trim())     { $p.Tenant = $script:TbTenant.Text.Trim() }
    $p
}
$script:BtnPreviewSchedule.Add_Click({
    if (-not (Get-Command Get-SPScheduledCommand -ErrorAction SilentlyContinue)) { Set-Status 'Scheduler helper not found (scripts/scheduled).'; return }
    $p = Get-SchedParams
    if (-not $p.SiteUrl) { Set-Status 'Enter a site URL to schedule.'; return }
    if (-not $p.Reports.Count) { Set-Status 'Pick at least one report.'; return }
    $script:TbSchedCommand.Text = (Get-SPScheduledCommand @p).CommandLine
    Set-Status 'Command ready — copy it, or click Create task.'
})
$script:BtnCreateSchedule.Add_Click({
    $p = Get-SchedParams
    if (-not $p.SiteUrl) { Set-Status 'Enter a site URL to schedule.'; return }
    if (-not $p.Reports.Count) { Set-Status 'Pick at least one report.'; return }
    $freq = @('Daily', 'Weekly')[$script:CbSchedFreq.SelectedIndex]
    $at = $script:TbSchedAt.Text.Trim(); if (-not $at) { $at = '07:00' }
    if (-not (Confirm-Action "Create a $freq task to report on`n$($p.SiteUrl) at $at ?")) { Set-Status 'Cancelled.'; return }
    $rp = $p.Clone(); $rp.Frequency = $freq; $rp.At = $at
    $regScript = Join-Path (Split-Path $here -Parent) 'scripts\scheduled\Register-GovernanceReportTask.ps1'
    Invoke-Worker -Command $regScript -Parameters $rp -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Schedule failed: $err"; return }
        Set-Status "Scheduled task created ($($result.TaskName))."
    }
})

# --- navigation -------------------------------------------------------------------------
$script:ViewMap = [ordered]@{
    Home     = $script:ViewHome; Connect = $script:ViewConnect; Migrate = $script:ViewMigrate
    PreCheck = $script:ViewPreCheck; Provision = $script:ViewProvision; Reports = $script:ViewReports; Scheduled = $script:ViewScheduled
}
$script:CrumbMap = @{ Home = 'Home'; Connect = 'Connect'; Migrate = 'Migrate'; PreCheck = 'Pre-check'; Provision = 'Provision'; Reports = 'Reports'; Scheduled = 'Scheduled' }
$script:GroupMap = @{ Home = 'Migration'; Connect = 'Migration'; Migrate = 'Migration'; PreCheck = 'Migration'; Provision = 'Migration'; Reports = 'Governance'; Scheduled = 'Governance' }

function Show-View([string]$name) {
    foreach ($entry in $script:ViewMap.GetEnumerator()) {
        $entry.Value.Visibility = if ($entry.Key -eq $name) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
    $script:Breadcrumb.Text = "$($script:GroupMap[$name])  ›  $($script:CrumbMap[$name])"
}

$script:NavHome.Add_Checked({ Show-View 'Home' })
$script:NavConnect.Add_Checked({ Show-View 'Connect' })
$script:NavMigrate.Add_Checked({ Show-View 'Migrate' })
$script:NavPreCheck.Add_Checked({ Show-View 'PreCheck' })
$script:NavProvision.Add_Checked({ Show-View 'Provision' })
$script:NavReports.Add_Checked({ Show-View 'Reports' })
$script:NavScheduled.Add_Checked({ Show-View 'Scheduled' })

$script:CardMigrate.Add_Click({ $script:NavMigrate.IsChecked = $true })
$script:CardPreCheck.Add_Click({ $script:NavPreCheck.IsChecked = $true })
$script:CardReports.Add_Click({ $script:NavReports.IsChecked = $true })
$script:CardProvision.Add_Click({ $script:NavProvision.IsChecked = $true })
$script:CardScheduled.Add_Click({ $script:NavScheduled.IsChecked = $true })

# Open on Home.
$script:NavHome.IsChecked = $true

# --- shutdown ---------------------------------------------------------------------------
$window.Add_Closing({
    try { if ($script:Worker) { $script:Worker.Close(); $script:Worker.Dispose() } } catch { }
})

$null = $window.ShowDialog()
