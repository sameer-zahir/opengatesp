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
$script:LastExplore = @()
$script:AppVersion = '0.10.0'

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
    <!-- Keyboard focus ring (visible on Tab; keyboard-only by WPF design) -->
    <Style x:Key="FocusVisual">
        <Setter Property="Control.Template">
            <Setter.Value>
                <ControlTemplate>
                    <Rectangle Margin="-3" StrokeThickness="2" Stroke="{DynamicResource Accent}"
                               RadiusX="9" RadiusY="9" SnapsToDevicePixels="True"/>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
    <Style x:Key="Muted" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
        <Setter Property="FontSize" Value="12"/>
    </Style>
    <Style x:Key="Section" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style TargetType="Button">
        <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
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
        <Setter Property="Foreground" Value="{DynamicResource WarnFg}"/>
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
        <Setter Property="FontSize" Value="12"/>
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
            <DataTrigger Binding="{Binding Status}" Value="Error"><Setter Property="Foreground" Value="{DynamicResource Danger}"/></DataTrigger>
            <DataTrigger Binding="{Binding Status}" Value="Warning"><Setter Property="Foreground" Value="{DynamicResource Warn}"/></DataTrigger>
            <DataTrigger Binding="{Binding Status}" Value="Skipped"><Setter Property="Foreground" Value="{DynamicResource FgMute}"/></DataTrigger>
        </Style.Triggers>
    </Style>

    <!-- Sidebar nav -->
    <Style x:Key="NavGroupHeader" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="11"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Margin" Value="14,2,0,6"/>
    </Style>
    <Style x:Key="NavButton" TargetType="RadioButton">
        <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="14"/>
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

    <!-- Nav icon (Segoe MDL2 Assets — present on Win10+) -->
    <Style x:Key="NavIcon" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
        <Setter Property="FontSize" Value="15"/>
        <Setter Property="Width" Value="26"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <!-- Home cards -->
    <Style x:Key="Card" TargetType="Button">
        <Setter Property="FocusVisualStyle" Value="{StaticResource FocusVisual}"/>
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
        <Setter Property="FontSize" Value="16"/>
        <Setter Property="FontWeight" Value="Bold"/>
    </Style>
    <Style x:Key="CardBody" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
        <Setter Property="Margin" Value="0,8,0,0"/>
    </Style>
    <Style x:Key="CardMeta" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontFamily" Value="Consolas"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Margin" Value="0,12,0,0"/>
    </Style>
    <Style x:Key="Breadcrumb" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="EmptyState" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{DynamicResource FgMute}"/>
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
    <SolidColorBrush x:Key="FgMute" Color="#9AA5D6"/>
    <SolidColorBrush x:Key="FgFaint" Color="#8C95C6"/>
    <SolidColorBrush x:Key="Accent" Color="#82AAFF"/>
    <SolidColorBrush x:Key="AccentHover" Color="#A2BFFF"/>
    <SolidColorBrush x:Key="AccentFg" Color="#1B1D2B"/>
    <SolidColorBrush x:Key="Border" Color="#353A57"/>
    <SolidColorBrush x:Key="BorderStrong" Color="#444A73"/>
    <SolidColorBrush x:Key="Good" Color="#C3E88D"/>
    <SolidColorBrush x:Key="GoodFg" Color="#1B1D2B"/>
    <SolidColorBrush x:Key="Warn" Color="#FFC777"/>
    <SolidColorBrush x:Key="WarnFg" Color="#1B1D2B"/>
    <SolidColorBrush x:Key="Danger" Color="#FF757F"/>
    <SolidColorBrush x:Key="DangerFg" Color="#1B1D2B"/>
</ResourceDictionary>
'@

$script:XamlLight = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <SolidColorBrush x:Key="Bg" Color="#FBF1C7"/>
    <SolidColorBrush x:Key="BgElev" Color="#F2E5BC"/>
    <SolidColorBrush x:Key="BgElev2" Color="#EBDBB2"/>
    <SolidColorBrush x:Key="Fg" Color="#3C3836"/>
    <SolidColorBrush x:Key="FgMute" Color="#665C54"/>
    <SolidColorBrush x:Key="FgFaint" Color="#7C6F64"/>
    <SolidColorBrush x:Key="Accent" Color="#D65D0E"/>
    <SolidColorBrush x:Key="AccentHover" Color="#AF3A03"/>
    <SolidColorBrush x:Key="AccentFg" Color="#FFF8E8"/>
    <SolidColorBrush x:Key="Border" Color="#E6D9AD"/>
    <SolidColorBrush x:Key="BorderStrong" Color="#D5C4A1"/>
    <SolidColorBrush x:Key="Good" Color="#427B58"/>
    <SolidColorBrush x:Key="GoodFg" Color="#FFF8E8"/>
    <SolidColorBrush x:Key="Warn" Color="#B57614"/>
    <SolidColorBrush x:Key="WarnFg" Color="#FFF8E8"/>
    <SolidColorBrush x:Key="Danger" Color="#9D0006"/>
    <SolidColorBrush x:Key="DangerFg" Color="#FFF8E8"/>
</ResourceDictionary>
'@

$script:XamlFluentLight = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <SolidColorBrush x:Key="Bg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="BgElev" Color="#F3F2F1"/>
    <SolidColorBrush x:Key="BgElev2" Color="#E9E7E5"/>
    <SolidColorBrush x:Key="Fg" Color="#1B1A19"/>
    <SolidColorBrush x:Key="FgMute" Color="#5D5A58"/>
    <SolidColorBrush x:Key="FgFaint" Color="#797775"/>
    <SolidColorBrush x:Key="Accent" Color="#0078D4"/>
    <SolidColorBrush x:Key="AccentHover" Color="#106EBE"/>
    <SolidColorBrush x:Key="AccentFg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Border" Color="#E1DFDD"/>
    <SolidColorBrush x:Key="BorderStrong" Color="#C8C6C4"/>
    <SolidColorBrush x:Key="Good" Color="#0E700E"/>
    <SolidColorBrush x:Key="GoodFg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Warn" Color="#8A6A00"/>
    <SolidColorBrush x:Key="WarnFg" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="Danger" Color="#A4262C"/>
    <SolidColorBrush x:Key="DangerFg" Color="#FFFFFF"/>
</ResourceDictionary>
'@

$script:XamlFluentDark = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <SolidColorBrush x:Key="Bg" Color="#1F1F1F"/>
    <SolidColorBrush x:Key="BgElev" Color="#2B2B2B"/>
    <SolidColorBrush x:Key="BgElev2" Color="#383838"/>
    <SolidColorBrush x:Key="Fg" Color="#F3F2F1"/>
    <SolidColorBrush x:Key="FgMute" Color="#C8C6C4"/>
    <SolidColorBrush x:Key="FgFaint" Color="#A5A3A1"/>
    <SolidColorBrush x:Key="Accent" Color="#479EF5"/>
    <SolidColorBrush x:Key="AccentHover" Color="#6CB2EE"/>
    <SolidColorBrush x:Key="AccentFg" Color="#1B1A19"/>
    <SolidColorBrush x:Key="Border" Color="#3B3A39"/>
    <SolidColorBrush x:Key="BorderStrong" Color="#4F4D4B"/>
    <SolidColorBrush x:Key="Good" Color="#6CCB5F"/>
    <SolidColorBrush x:Key="GoodFg" Color="#1F1F1F"/>
    <SolidColorBrush x:Key="Warn" Color="#FCD34D"/>
    <SolidColorBrush x:Key="WarnFg" Color="#1F1F1F"/>
    <SolidColorBrush x:Key="Danger" Color="#F1707B"/>
    <SolidColorBrush x:Key="DangerFg" Color="#1F1F1F"/>
</ResourceDictionary>
'@

function Read-Dict([string]$xaml) { [Windows.Markup.XamlReader]::Parse($xaml) }
# Name -> theme dictionary XAML. Fluent Light is the default.
$script:Themes = [ordered]@{
    'Fluent Light' = $script:XamlFluentLight
    'Fluent Dark'  = $script:XamlFluentDark
    'Gruvbox'      = $script:XamlLight
    'Tokyo Night'  = $script:XamlDark
}

function Get-GuiTheme {
    $name = $null
    if (Test-Path -LiteralPath $script:GuiCfgPath) {
        try { $name = (Get-Content -LiteralPath $script:GuiCfgPath -Raw | ConvertFrom-Json).Theme } catch { }
    }
    # Any unknown or legacy ('Light'/'Dark') value falls through to the new default.
    if ($name -and $script:Themes.Contains($name)) { $name } else { 'Fluent Light' }
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
    if (-not $script:Themes.Contains($name)) { $name = 'Fluent Light' }
    $td = Read-Dict $script:Themes[$name]
    $md = $window.Resources.MergedDictionaries
    if ($script:ThemeDict) { [void]$md.Remove($script:ThemeDict) }
    $md.Insert(0, $td)
    $script:ThemeDict    = $td
    $script:CurrentTheme = $name
    Save-GuiTheme $name
}

# Apply the saved (or default) theme, then wire the styled theme picker.
$script:CurrentThemeName = Get-GuiTheme
Set-Theme $script:CurrentThemeName
$script:CbTheme.ItemsSource  = [string[]]@($script:Themes.Keys)
$script:CbTheme.SelectedItem = $script:CurrentThemeName
$script:CbTheme.Add_SelectionChanged({ if ($script:CbTheme.SelectedItem) { Set-Theme ([string]$script:CbTheme.SelectedItem) } })

# Fluid scale: grow the content area modestly on wider windows (clamped, never shrinks below 1.0).
function Update-UiScale {
    if (-not $script:UiScale) { return }
    $s = [Math]::Max(1.0, [Math]::Min(1.2, $window.ActualWidth / 1180))
    $script:UiScale.ScaleX = $s; $script:UiScale.ScaleY = $s
}
$window.Add_SizeChanged({ Update-UiScale })

# --- helpers ----------------------------------------------------------------------------
function Set-Status([string]$text) { $script:StatusText.Text = $text }

# Top-right toast — success auto-dismisses (5s), errors persist longer (10s); click to dismiss.
function Show-Toast([string]$Type, [string]$Title, [string]$Message) {
    if (-not $script:ToastHost) { return }
    $color = switch ($Type) { 'error' { 'Danger' } 'warn' { 'Warn' } default { 'Good' } }
    $x = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="8" Margin="0,0,0,10" Width="320" Cursor="Hand"
        Background="{DynamicResource BgElev2}" BorderBrush="{DynamicResource Border}" BorderThickness="1">
  <Grid>
    <Border Width="4" HorizontalAlignment="Left" CornerRadius="8,0,0,8" Background="{DynamicResource $color}"/>
    <StackPanel Margin="16,10,12,10">
      <TextBlock x:Name="ToastTitle" FontWeight="SemiBold" Foreground="{DynamicResource Fg}" TextWrapping="Wrap"/>
      <TextBlock x:Name="ToastMsg" Foreground="{DynamicResource FgMute}" FontSize="12" TextWrapping="Wrap" Margin="0,2,0,0"/>
    </StackPanel>
  </Grid>
</Border>
"@
    try {
        $b = [Windows.Markup.XamlReader]::Parse($x)
        $b.FindName('ToastTitle').Text = $Title
        $m = $b.FindName('ToastMsg')
        if ($Message) { $m.Text = $Message } else { $m.Visibility = [System.Windows.Visibility]::Collapsed }
        $b.Add_MouseLeftButtonUp({ try { $script:ToastHost.Children.Remove($args[0]) } catch { } })
        $script:ToastHost.Children.Add($b) | Out-Null
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds($(if ($Type -eq 'error') { 10 } else { 5 }))
        $timer.Tag = $b
        $timer.Add_Tick({ $args[0].Stop(); try { $script:ToastHost.Children.Remove($args[0].Tag) } catch { } })
        $timer.Start()
    }
    catch { }
}

function Show-Onboarding {
    # First-run: guide the one-time (free) Entra app registration, in-app (not the console).
    $x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Welcome to OpenGateSP" Width="580" Height="500" WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="{DynamicResource Bg}" TextElement.Foreground="{DynamicResource Fg}" TextElement.FontFamily="Segoe UI" TextElement.FontSize="14">
  <StackPanel Margin="30">
    <TextBlock Text="Welcome to OpenGateSP" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource Fg}"/>
    <TextBlock TextWrapping="Wrap" Margin="0,8,0,18" Foreground="{DynamicResource FgMute}"
               Text="One quick, free, one-time setup: register your own Entra ID app so OpenGateSP can sign in to your tenant. It takes about two minutes."/>
    <TextBlock Text="1. Copy this command and run it in PowerShell" FontWeight="SemiBold" Margin="0,0,0,6" Foreground="{DynamicResource Fg}"/>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <TextBox x:Name="CmdBox" Grid.Column="0" IsReadOnly="True" TextWrapping="Wrap" FontFamily="Consolas" FontSize="12" Height="54"
               Text="Register-PnPEntraIDAppForInteractiveLogin -ApplicationName 'OpenGateSP' -Tenant &lt;you&gt;.onmicrosoft.com"/>
      <Button x:Name="CopyBtn" Grid.Column="1" Content="Copy" Width="64" Margin="8,5,0,5" VerticalAlignment="Top"/>
    </Grid>
    <TextBlock Text="2. Paste the Application (client) ID it returns, and your tenant" FontWeight="SemiBold" Margin="0,16,0,6" Foreground="{DynamicResource Fg}"/>
    <TextBlock Text="Application (client) ID" Foreground="{DynamicResource FgMute}" FontSize="12"/>
    <TextBox x:Name="ClientIdBox"/>
    <TextBlock Text="Tenant (e.g. contoso.onmicrosoft.com)" Foreground="{DynamicResource FgMute}" FontSize="12" Margin="0,8,0,0"/>
    <TextBox x:Name="TenantBox"/>
    <StackPanel Orientation="Horizontal" Margin="0,22,0,0">
      <Button x:Name="SaveBtn" Content="Save &amp; continue"/>
      <Button x:Name="SkipBtn" Content="Skip for now" Style="{DynamicResource GhostButton}"/>
      <Button x:Name="HelpBtn" Content="Need help?" Style="{DynamicResource GhostButton}"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    try {
        $w = [Windows.Markup.XamlReader]::Parse($x)
        $w.Resources.MergedDictionaries.Add($script:Controls)
        if ($script:ThemeDict) { $w.Resources.MergedDictionaries.Add($script:ThemeDict) }
        $cmdText = "Register-PnPEntraIDAppForInteractiveLogin -ApplicationName 'OpenGateSP' -Tenant <you>.onmicrosoft.com"
        $w.FindName('CopyBtn').Add_Click({ try { [System.Windows.Clipboard]::SetText($cmdText) } catch { } })
        $w.FindName('HelpBtn').Add_Click({ Start-Process 'https://github.com/sameer-zahir/opengatesp/blob/main/docs/02-entra-app-registration.md' })
        $w.FindName('SkipBtn').Add_Click({ $w.Close() })
        $w.FindName('SaveBtn').Add_Click({
            $cid = $w.FindName('ClientIdBox').Text.Trim()
            $tenant = $w.FindName('TenantBox').Text.Trim()
            if (-not $cid) { [System.Windows.MessageBox]::Show('Paste the Application (client) ID first, or choose Skip for now.', 'OpenGateSP') | Out-Null; return }
            $dir = Join-Path $env:APPDATA 'OpenGateSP'
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            @{ ClientId = $cid; Tenant = $tenant } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'spconfig.json') -Encoding utf8
            $script:TbClientId.Text = $cid
            if ($tenant) { $script:TbTenant.Text = $tenant }
            $w.Close()
        })
        $w.ShowDialog() | Out-Null
    }
    catch { }
}

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
            $script:SetConnSummary.Text = "Connected to $($r.Url)"
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
        0 { $cmd = 'Get-SPSharingReport';     $p = @{ SiteUrl = $site; IncludeLinks = $incl } }
        1 { $cmd = 'Get-SPPermissionReport';  $p = @{ SiteUrl = $site; IncludeListPermissions = $incl } }
        2 { $cmd = 'Get-SPSiteInventory';     $p = @{ IncludeStorage = $true } }
        3 { $cmd = 'Get-SPPermissionsMatrix'; $p = @{ SiteUrl = $site; IncludeListPermissions = $incl } }
        4 { $cmd = 'Get-SPOrphanedUsers';     $p = @{ SiteUrl = $site } }
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

function Invoke-Lifecycle([bool]$Preview) {
    $site = $script:TbReportSite.Text.Trim()
    if (-not $site) { Set-Status 'Enter a Site URL (above) for a lifecycle action.'; return }
    $state = @('ReadOnly', 'NoAccess', 'Unlock')[$script:CbLifecycle.SelectedIndex]
    $p = @{ SiteUrl = $site; LockState = $state }
    if ($Preview) {
        $p.WhatIf = $true
    }
    else {
        if (-not (Confirm-Action "Set lock state of`n$site`nto $state ?`n`nRequires SharePoint admin.")) { return }
        $p.Force = $true
    }
    Invoke-Worker -Command 'Set-SPSiteLifecycle' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Lifecycle failed: $err"; return }
        $script:LastReport = Show-Grid $script:GridReport $result $script:EmptyReport
        Set-Status "Lifecycle: $($script:LastReport.Count) row(s)."
    }
}
$script:BtnLifecyclePreview.Add_Click({ Invoke-Lifecycle $true })
$script:BtnLifecycleApply.Add_Click({ Invoke-Lifecycle $false })

# --- Explore (SharePoint source assessment) --------------------------------------------
$script:BtnRunExplore.Add_Click({
    $site = $script:TbExploreSite.Text.Trim()
    $mb = 100; $tmp = 0
    if ([int]::TryParse($script:TbExploreMB.Text.Trim(), [ref]$tmp)) { $mb = $tmp }
    $incl = [bool]$script:CbExploreVersions.IsChecked
    switch ($script:CbExplore.SelectedIndex) {
        0 { $cmd = 'Invoke-SPExplore';          $p = @{ SiteUrl = $site; LargeFileMB = $mb }; if ($incl) { $p.IncludeVersions = $true } }
        1 { $cmd = 'Get-SPCheckedOutFiles';     $p = @{ SiteUrl = $site } }
        2 { $cmd = 'Get-SPLargeFiles';          $p = @{ SiteUrl = $site; MinSizeMB = $mb } }
        3 { $cmd = 'Get-SPVersionHistoryReport'; $p = @{ SiteUrl = $site } }
        4 { $cmd = 'Get-SPContentInsights';     $p = @{ SiteUrl = $site } }
        5 { $cmd = 'Get-SPWorkflowReport';      $p = @{ SiteUrl = $site } }
        6 { $cmd = 'Get-SPInactiveSites';       $p = @{ InactiveDays = 180 } }
        default { return }
    }
    if ($cmd -ne 'Get-SPInactiveSites' -and -not $site) { Set-Status 'Enter a Site URL for this report.'; return }

    Invoke-Worker -Command $cmd -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Explore failed: $err"; return }
        $script:LastExplore = Show-Grid $script:GridExplore $result $script:EmptyExplore
        Set-Status "$($script:LastExplore.Count) finding(s)."
    }
})

$script:BtnExploreCsv.Add_Click({
    if (-not $script:LastExplore.Count) { Set-Status 'Nothing to export — run a report first.'; return }
    $path = Save-FilePath 'CSV (*.csv)|*.csv' 'explore.csv'
    if ($path) { $script:LastExplore | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8; Set-Status "Saved $path" }
})

$script:BtnExploreHtml.Add_Click({
    if (-not $script:LastExplore.Count) { Set-Status 'Nothing to export — run a report first.'; return }
    $path = Save-FilePath 'HTML (*.html)|*.html' 'explore.html'
    if ($path) {
        $style = '<style>body{font-family:Segoe UI,Arial;background:#1b1d2b;color:#c0caf5}table{border-collapse:collapse;width:100%}th,td{border:1px solid #3b4261;padding:6px 10px;text-align:left}th{background:#24283b;color:#7aa2f7}</style>'
        $script:LastExplore | ConvertTo-Html -Head $style | Out-File -LiteralPath $path -Encoding utf8
        Set-Status "Saved $path"
    }
})

function Invoke-Remediation([bool]$Preview) {
    $site = $script:TbExploreSite.Text.Trim()
    if (-not $site) { Set-Status 'Enter a Site URL to remediate.'; return }
    switch ($script:CbRemediate.SelectedIndex) {
        0 { $cmd = 'Invoke-SPCheckIn';        $p = @{ SiteUrl = $site } }
        1 { $cmd = 'Remove-SPOrphanedUsers';  $p = @{ SiteUrl = $site } }
        default { return }
    }
    if ($Preview) {
        $p.WhatIf = $true
    }
    else {
        $label = "$($script:CbRemediate.SelectedItem.Content)"
        if (-not (Confirm-Action "Apply '$label' to $site? This writes to SharePoint.")) { return }
        $p.Force = $true
    }
    Invoke-Worker -Command $cmd -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Remediation failed: $err"; Show-Toast 'error' 'Remediation failed' "$err"; return }
        $script:LastExplore = Show-Grid $script:GridExplore $result $script:EmptyExplore
        Set-Status "$($script:LastExplore.Count) row(s)."
        Show-Toast 'success' 'Remediation applied' "$($script:LastExplore.Count) item(s)"
    }
}
$script:BtnRemediatePreview.Add_Click({ Invoke-Remediation $true })
$script:BtnRemediateApply.Add_Click({ Invoke-Remediation $false })

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

# --- Copy site (SharePoint → SharePoint) ------------------------------------------------
function Invoke-CopySite([bool]$Preview) {
    $src = $script:TbCopySource.Text.Trim()
    $dst = $script:TbCopyDest.Text.Trim()
    if (-not $src -or -not $dst) { Set-Status 'Source and destination site URLs are required.'; return }
    if ($src.TrimEnd('/') -ieq $dst.TrimEnd('/')) { Set-Status 'Source and destination must be different sites.'; return }

    $p = @{
        SourceUrl      = $src
        DestinationUrl = $dst
        ConflictMode   = @('IfNewer', 'Skip', 'KeepBoth', 'Replace')[$script:CbCopyConflict.SelectedIndex]
    }
    if ($script:CbCopyContent.IsChecked)  { $p.IncludeContent = $true }
    if ($script:CbCopyVersions.IsChecked) { $p.IncludeVersions = $true }
    if ($script:CbCopyPerms.IsChecked)    { $p.CopyPermissions = $true }
    $lists = $script:TbCopyLists.Text.Trim()
    if ($lists) { $p.Lists = @($lists -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

    if ($Preview) {
        $p.WhatIf = $true
        $script:CopyVerb = 'planned'
    }
    else {
        $what = if ($p.IncludeContent) { 'structure + content' } else { 'structure' }
        if (-not (Confirm-Action "Copy $what from`n$src`nto`n$dst ?`n`nRun a preview first if you haven't.")) { Set-Status 'Cancelled.'; return }
        $p.Force = $true
        $script:CopyVerb = 'copied'
    }

    Invoke-Worker -Command 'Copy-SPSite' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Copy failed: $err"; return }
        $rows = @(Show-Grid $script:GridCopy $result $script:EmptyCopy)
        $errs = @($rows | Where-Object Status -eq 'Error').Count
        $tail = if ($errs) { " — $errs error(s), see ./logs" } else { ' — see ./logs for the transcript.' }
        Set-Status "$($rows.Count) object(s) $($script:CopyVerb)$tail"
    }
}
$script:BtnPreviewCopy.Add_Click({ Invoke-CopySite $true })
$script:BtnRunCopy.Add_Click({ Invoke-CopySite $false })
$script:BtnValidateCopy.Add_Click({
    $src = $script:TbCopySource.Text.Trim()
    $dst = $script:TbCopyDest.Text.Trim()
    if (-not $src -or -not $dst) { Set-Status 'Enter source and destination site URLs to validate.'; return }
    $p = @{ SourceUrl = $src; DestinationUrl = $dst }
    $listsText = $script:TbCopyLists.Text.Trim()
    if ($listsText) { $p.Lists = @($listsText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    Invoke-Worker -Command 'Compare-SPSite' -Parameters $p -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Validate failed: $err"; return }
        $rows = Show-Grid $script:GridCopy $result $script:EmptyCopy
        Set-Status "$($rows.Count) object(s) compared."
    }
})

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

# --- Collaboration (Teams / Groups / Planner) ------------------------------------------
function Invoke-Collab([string]$Command, [hashtable]$Params, [bool]$Preview, [string]$Need) {
    foreach ($k in ($Need -split ',')) { if (-not $Params[$k.Trim()]) { Set-Status 'Fill in every field for this action.'; return } }
    if ($Preview) {
        $Params.WhatIf = $true
    }
    else {
        if (-not (Confirm-Action "Create via $Command ? This writes to Microsoft 365.")) { return }
        $Params.Force = $true
    }
    Invoke-Worker -Command $Command -Parameters $Params -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Create failed: $err"; return }
        $rows = Show-Grid $script:GridCollab $result $script:EmptyCollab
        Set-Status "$($rows.Count) row(s)."
    }
}
$script:BtnPreviewGroup.Add_Click({ Invoke-Collab 'Copy-SPM365Group' @{ SourceIdentity = $script:TbGroupSource.Text.Trim(); DisplayName = $script:TbGroupName.Text.Trim(); MailNickname = $script:TbGroupAlias.Text.Trim() } $true 'SourceIdentity,DisplayName,MailNickname' })
$script:BtnCreateGroup.Add_Click({ Invoke-Collab 'Copy-SPM365Group' @{ SourceIdentity = $script:TbGroupSource.Text.Trim(); DisplayName = $script:TbGroupName.Text.Trim(); MailNickname = $script:TbGroupAlias.Text.Trim() } $false 'SourceIdentity,DisplayName,MailNickname' })
$script:BtnPreviewTeam.Add_Click({ Invoke-Collab 'Copy-SPTeam' @{ SourceTeam = $script:TbTeamSource.Text.Trim(); DisplayName = $script:TbTeamName.Text.Trim(); MailNickname = $script:TbTeamAlias.Text.Trim() } $true 'SourceTeam,DisplayName,MailNickname' })
$script:BtnCreateTeam.Add_Click({ Invoke-Collab 'Copy-SPTeam' @{ SourceTeam = $script:TbTeamSource.Text.Trim(); DisplayName = $script:TbTeamName.Text.Trim(); MailNickname = $script:TbTeamAlias.Text.Trim() } $false 'SourceTeam,DisplayName,MailNickname' })
$script:BtnPreviewPlan.Add_Click({ Invoke-Collab 'Copy-SPPlannerPlan' @{ SourcePlanId = $script:TbPlanSource.Text.Trim(); DestinationGroupId = $script:TbPlanGroup.Text.Trim(); Title = $script:TbPlanTitle.Text.Trim() } $true 'SourcePlanId,DestinationGroupId,Title' })
$script:BtnCreatePlan.Add_Click({ Invoke-Collab 'Copy-SPPlannerPlan' @{ SourcePlanId = $script:TbPlanSource.Text.Trim(); DestinationGroupId = $script:TbPlanGroup.Text.Trim(); Title = $script:TbPlanTitle.Text.Trim() } $false 'SourcePlanId,DestinationGroupId,Title' })

# --- Copy chooser + guided wizard ------------------------------------------------------
$script:CopyCtx = [ordered]@{ Type = 'structure' }
$script:WizStep = 1
$script:WizPreviewHash = $null
$script:Tasks = @()
$script:RecentCopies = @()
$script:WizTitles = @{ structure = 'Structure & content'; structureonly = 'Structure only'; content = 'Content only'; list = 'A list or library' }

function Add-TaskRow([string]$Operation, [string]$Target, [string]$Result) {
    $row = [pscustomobject]@{ Time = (Get-Date).ToString('HH:mm:ss'); Operation = $Operation; Target = $Target; Result = $Result }
    $script:Tasks = @($row) + @($script:Tasks)
    Show-Grid $script:GridTasks $script:Tasks $script:EmptyTasks | Out-Null
}
function Add-RecentCopy([string]$Result) {
    $row = [pscustomobject]@{ Type = $script:WizTitles[$script:CopyCtx.Type]; Source = $script:TbWizSource.Text.Trim(); Destination = $script:TbWizDest.Text.Trim(); Result = $Result; When = (Get-Date).ToString('g') }
    $script:RecentCopies = @($row) + @($script:RecentCopies)
    Show-Grid $script:GridRecent $script:RecentCopies $script:EmptyRecent | Out-Null
}

function Build-CopyParams([bool]$Preview) {
    $type = $script:CopyCtx.Type
    $conflict = @('IfNewer', 'Skip', 'KeepBoth', 'Replace')[$script:CbWizConflict.SelectedIndex]
    $p = [ordered]@{ SourceUrl = $script:TbWizSource.Text.Trim(); DestinationUrl = $script:TbWizDest.Text.Trim(); ConflictMode = $conflict }
    if ($script:CbWizContent.IsChecked -or $type -eq 'content') { $p.IncludeContent = $true }
    if ($script:CbWizVersions.IsChecked) { $p.IncludeVersions = $true }
    if ($script:CbWizPerms.IsChecked) { $p.CopyPermissions = $true }
    $since = $script:TbWizSince.Text.Trim()
    if ($since) { try { $p.Since = [datetime]$since } catch { } }
    $lists = $script:TbWizLists.Text.Trim()
    $cmd = 'Copy-SPSite'
    if ($type -eq 'list') {
        $cmd = 'Copy-SPList'
        if ($p.Contains('CopyPermissions')) { $p.Remove('CopyPermissions') }
        if ($lists) { $p.List = (($lists -split ',')[0]).Trim() }
    }
    elseif ($lists) {
        $p.Lists = @($lists -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if ($Preview) { $p.WhatIf = $true } else { $p.Force = $true }
    @{ Command = $cmd; Params = $p }
}
function Get-WizardParamHash {
    $bp = Build-CopyParams $true
    (($bp.Params.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '|') + "|$($bp.Command)"
}
function Get-WizardSummary {
    $t = $script:WizTitles[$script:CopyCtx.Type]
    $lists = $script:TbWizLists.Text.Trim()
    $scope = if ($lists) { $lists } else { 'all lists & libraries' }
    $conf = @('Copy if newer', "Don't copy", 'Keep both', 'Copy and replace')[$script:CbWizConflict.SelectedIndex]
    $opts = @(); if ($script:CbWizContent.IsChecked) { $opts += 'content' }; if ($script:CbWizVersions.IsChecked) { $opts += 'versions' }; if ($script:CbWizPerms.IsChecked) { $opts += 'permissions' }
    $inc = if ($opts.Count) { ($opts -join ', ') } else { 'schema only' }
    "$t`nFrom:  $($script:TbWizSource.Text.Trim())`nTo:     $($script:TbWizDest.Text.Trim())`nScope: $scope`nOn conflict: $conf   ·   Include: $inc"
}

function Update-WizardNav {
    $ok = $true
    switch ($script:WizStep) {
        1 { $ok = [bool]($script:TbWizSource.Text.Trim()) }
        2 { $s = $script:TbWizSource.Text.Trim(); $d = $script:TbWizDest.Text.Trim(); $ok = ($d -and ($s.TrimEnd('/') -ne $d.TrimEnd('/'))) }
        default { $ok = $true }
    }
    $script:BtnWizNext.IsEnabled = $ok
}
function Set-WizardStep([int]$n) {
    $script:WizStep = $n
    $vis = [System.Windows.Visibility]::Visible; $col = [System.Windows.Visibility]::Collapsed
    $panels = @($script:PanelWizSource, $script:PanelWizDest, $script:PanelWizScope, $script:PanelWizOptions, $script:PanelWizRun)
    for ($i = 0; $i -lt $panels.Count; $i++) { $panels[$i].Visibility = if (($i + 1) -eq $n) { $vis } else { $col } }
    $steps = @($script:WizStep1, $script:WizStep2, $script:WizStep3, $script:WizStep4, $script:WizStep5)
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $steps[$i].SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $(if (($i + 1) -le $n) { 'Accent' } else { 'FgMute' }))
        $steps[$i].FontWeight = if (($i + 1) -le $n) { 'Bold' } else { 'Normal' }
    }
    $script:WizStepLabel.Text = "Step $n of 5"
    $isRun = ($n -eq 5)
    $script:BtnWizBack.Visibility = if ($n -gt 1) { $vis } else { $col }
    $script:BtnWizNext.Visibility = if ($isRun) { $col } else { $vis }
    $script:BtnWizPreview.Visibility = if ($isRun) { $vis } else { $col }
    $script:BtnWizRun.Visibility = if ($isRun) { $vis } else { $col }
    if ($isRun) {
        $script:WizSummary.Text = Get-WizardSummary
        $script:BtnWizRun.IsEnabled = ($script:WizPreviewHash -and $script:WizPreviewHash -eq (Get-WizardParamHash))
    }
    Update-WizardNav
}
function Open-CopyWizard([string]$Type) {
    $script:CopyCtx = [ordered]@{ Type = $Type }
    $script:WizPreviewHash = $null
    $script:TbWizSource.Text = ''; $script:TbWizDest.Text = ''; $script:TbWizLists.Text = ''; $script:TbWizSince.Text = ''
    $script:CbWizContent.IsChecked = ($Type -ne 'structureonly')
    $script:CbWizVersions.IsChecked = $false; $script:CbWizPerms.IsChecked = $false
    $script:CbWizConflict.SelectedIndex = 0
    $script:WizTypeChip.Text = $script:WizTitles[$Type]
    Show-Grid $script:GridWizResult @() $script:EmptyWizResult | Out-Null
    Show-Grid $script:GridWizScope @() $script:EmptyWizScope | Out-Null
    $script:NavCopy.IsChecked = $true
    Show-View 'CopyWizard'
    Set-WizardStep 1
}

function Invoke-CopyPreview {
    $bp = Build-CopyParams $true
    Invoke-Worker -Command $bp.Command -Parameters $bp.Params -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Preview failed: $err"; return }
        $rows = @(Show-Grid $script:GridWizResult $result $script:EmptyWizResult)
        $script:WizPreviewHash = Get-WizardParamHash
        $script:BtnWizRun.IsEnabled = $true
        Set-Status "Preview: $($rows.Count) object(s). Review the plan, then Run copy."
    }
}
function Invoke-CopyRun {
    if (-not (Confirm-Action "Run this copy?`n`n$(Get-WizardSummary)`n`nNothing was written by the preview.")) { return }
    $bp = Build-CopyParams $false
    $tgt = "$($script:TbWizSource.Text.Trim()) -> $($script:TbWizDest.Text.Trim())"
    Invoke-Worker -Command $bp.Command -Parameters $bp.Params -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Copy failed: $err"; Show-Toast 'error' 'Copy failed' "$err"; Add-TaskRow 'Copy' $tgt "Error: $err"; return }
        $rows = @(Show-Grid $script:GridWizResult $result $script:EmptyWizResult)
        $errs = @($rows | Where-Object Status -eq 'Error').Count
        $summary = "$($rows.Count) object(s), $errs error(s)"
        Set-Status "Copy complete — $summary. See ./logs for the transcript."
        Show-Toast $(if ($errs) { 'warn' } else { 'success' }) 'Copy complete' $summary
        Add-TaskRow 'Copy' $tgt $summary
        Add-RecentCopy $summary
    }
}

# Chooser cards
$script:CardCopyStructure.Add_Click({ Open-CopyWizard 'structure' })
$script:CardCopyStructureOnly.Add_Click({ Open-CopyWizard 'structureonly' })
$script:CardCopyContent.Add_Click({ Open-CopyWizard 'content' })
$script:CardCopyList.Add_Click({ Open-CopyWizard 'list' })
$script:CardCopyTeam.Add_Click({ Show-View 'Collab' })
$script:CardCopyGroup.Add_Click({ Show-View 'Collab' })
$script:CardCopyPlanner.Add_Click({ Show-View 'Collab' })
$script:CardImportFileShare.Add_Click({ Show-View 'Migrate' })

# Wizard controls
$script:BtnWizNext.Add_Click({ if ($script:WizStep -lt 5) { Set-WizardStep ($script:WizStep + 1) } })
$script:BtnWizBack.Add_Click({ if ($script:WizStep -gt 1) { Set-WizardStep ($script:WizStep - 1) } })
$script:BtnWizPreview.Add_Click({ Invoke-CopyPreview })
$script:BtnWizRun.Add_Click({ Invoke-CopyRun })
$script:BtnWizLoadLists.Add_Click({
    $s = $script:TbWizSource.Text.Trim(); $d = $script:TbWizDest.Text.Trim()
    if (-not $s -or -not $d) { Set-Status 'Enter source and destination (steps 1-2) before loading lists.'; return }
    Invoke-Worker -Command 'Compare-SPSite' -Parameters @{ SourceUrl = $s; DestinationUrl = $d } -OnDone {
        param($result, $err)
        if ($err) { Set-Status "Load lists failed: $err"; return }
        $rows = @(Show-Grid $script:GridWizScope $result $script:EmptyWizScope)
        Set-Status "$($rows.Count) list(s)/librar(ies) compared."
    }
})
$script:TbWizSource.Add_TextChanged({ Update-WizardNav })
$script:TbWizDest.Add_TextChanged({ Update-WizardNav })

# --- Settings ---------------------------------------------------------------------------
$script:SetAbout.Text = "OpenGateSP $script:AppVersion"
$script:BtnSettings.Add_Click({ Show-View 'Settings' })
$script:ConnPill.Add_MouseLeftButtonUp({ Show-View 'Settings' })
$script:BtnManageConnection.Add_Click({ Show-View 'Connect' })
$script:BtnDocs.Add_Click({ Start-Process 'https://github.com/sameer-zahir/opengatesp#readme' })
$script:BtnOpenLogs.Add_Click({
    $logs = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
    $target = if (Test-Path -LiteralPath $logs) { $logs } else { Split-Path $PSScriptRoot -Parent }
    Start-Process -FilePath explorer.exe -ArgumentList $target
})
$script:BtnCheckUpdates.Add_Click({
    Set-Status 'Checking for updates...'
    try {
        $r = Invoke-RestMethod 'https://api.github.com/repos/sameer-zahir/opengatesp/releases/latest' -Headers @{ 'User-Agent' = 'OpenGateSP' } -TimeoutSec 12
        $latest = "$($r.tag_name)".TrimStart('v')
        if ($latest -and [version]$latest -gt [version]$script:AppVersion) {
            if (Confirm-Action "OpenGateSP $latest is available (you have $script:AppVersion).`n`nOpen the download page?") { Start-Process "$($r.html_url)" }
            Set-Status "Update available: $latest"
        }
        else { Set-Status "You're on the latest version ($script:AppVersion)." }
    }
    catch { Set-Status "Update check failed: $($_.Exception.Message)" }
})

# --- navigation -------------------------------------------------------------------------
$script:ViewMap = [ordered]@{
    Home = $script:ViewHome; Connect = $script:ViewConnect; Explore = $script:ViewExplore
    CopyLanding = $script:ViewCopyLanding; CopyWizard = $script:ViewCopyWizard
    Migrate = $script:ViewMigrate; CopySite = $script:ViewCopySite; Collab = $script:ViewCollab
    PreCheck = $script:ViewPreCheck; Provision = $script:ViewProvision; Reports = $script:ViewReports
    Tasks = $script:ViewTasks; Scheduled = $script:ViewScheduled; Settings = $script:ViewSettings
}
$script:CrumbMap = @{ Home = 'Home'; Connect = 'Connect'; Explore = 'Explore'; CopyLanding = 'Copy'; CopyWizard = 'Copy'; Migrate = 'Import file share'; CopySite = 'Copy site'; Collab = 'Teams & Groups'; PreCheck = 'Pre-check'; Provision = 'Provisioning'; Reports = 'Security'; Tasks = 'Tasks'; Scheduled = 'Scheduled'; Settings = 'Settings' }
$script:GroupMap = @{ Home = 'Migration'; Connect = 'Setup'; Explore = 'Migration'; CopyLanding = 'Migration'; CopyWizard = 'Migration'; Migrate = 'Migration'; CopySite = 'Migration'; Collab = 'Migration'; PreCheck = 'Migration'; Provision = 'Governance'; Reports = 'Migration'; Tasks = 'Activity'; Scheduled = 'Activity'; Settings = 'Setup' }

function Show-View([string]$name) {
    foreach ($entry in $script:ViewMap.GetEnumerator()) {
        $entry.Value.Visibility = if ($entry.Key -eq $name) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
    $script:Breadcrumb.Text = "$($script:GroupMap[$name])  ›  $($script:CrumbMap[$name])"
}

$script:NavHome.Add_Checked({ Show-View 'Home' })
$script:NavConnect.Add_Checked({ Show-View 'Connect' })
$script:NavExplore.Add_Checked({ Show-View 'Explore' })
$script:NavCopy.Add_Checked({ Show-View 'CopyLanding' })
$script:NavPreCheck.Add_Checked({ Show-View 'PreCheck' })
$script:NavReports.Add_Checked({ Show-View 'Reports' })
$script:NavTasks.Add_Checked({ Show-View 'Tasks' })
$script:NavScheduled.Add_Checked({ Show-View 'Scheduled' })
$script:NavProvision.Add_Checked({ Show-View 'Provision' })

$script:CardMigrate.Add_Click({ $script:NavCopy.IsChecked = $true })
$script:CardCopySite.Add_Click({ $script:NavCopy.IsChecked = $true })
$script:CardPreCheck.Add_Click({ $script:NavPreCheck.IsChecked = $true })
$script:CardExplore.Add_Click({ $script:NavExplore.IsChecked = $true })
$script:CardReports.Add_Click({ $script:NavReports.IsChecked = $true })
$script:CardProvision.Add_Click({ $script:NavProvision.IsChecked = $true })
$script:CardScheduled.Add_Click({ $script:NavScheduled.IsChecked = $true })

# --- keyboard shortcuts -----------------------------------------------------------------
$window.Add_PreviewKeyDown({
    $ke = $args[1]
    $inText = $ke.OriginalSource -is [System.Windows.Controls.TextBox]
    $vis = [System.Windows.Visibility]::Visible; $col = [System.Windows.Visibility]::Collapsed
    if ($ke.Key -eq 'Escape' -and $script:ShortcutsOverlay.Visibility -eq $vis) { $script:ShortcutsOverlay.Visibility = $col; $ke.Handled = $true; return }
    if (-not $inText -and $ke.Key -eq 'OemQuestion') {
        $script:ShortcutsOverlay.Visibility = if ($script:ShortcutsOverlay.Visibility -eq $vis) { $col } else { $vis }
        $ke.Handled = $true; return
    }
    if ($ke.Key -eq 'OemComma' -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        Show-View 'Settings'; $ke.Handled = $true
    }
})
$script:ShortcutsOverlay.Add_MouseLeftButtonDown({ $script:ShortcutsOverlay.Visibility = [System.Windows.Visibility]::Collapsed })

# Open on Home.
$script:NavHome.IsChecked = $true

# --- shutdown ---------------------------------------------------------------------------
$window.Add_Closing({
    try { if ($script:Worker) { $script:Worker.Close(); $script:Worker.Dispose() } } catch { }
})

try {
    $icoPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\opengatesp.ico'
    if (Test-Path -LiteralPath $icoPath) { $window.Icon = New-Object System.Windows.Media.Imaging.BitmapImage ([Uri]$icoPath) }
} catch { }

# First run: guide the one-time Entra app setup before the main window opens.
if (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA 'OpenGateSP\spconfig.json'))) { Show-Onboarding }

$null = $window.ShowDialog()
