using System;
using System.Collections;
using System.Collections.Generic;

public class TerminalCapability
{
    public string HostName { get; set; }
    public string OS { get; set; }
    public string PSVersion { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public bool AnsiSupport { get; set; }
    public bool TrueColorSupport { get; set; }
    public bool Color256Support { get; set; }
    public bool UnicodeSupport { get; set; }
    public bool Interactive { get; set; }
    public bool AlternateBuffer { get; set; }
    public bool SixelSupport { get; set; }
    public bool KittyGraphics { get; set; }
    public bool ITermImages { get; set; }
    public bool IsRedirected { get; set; }
    public Hashtable EnvironmentVars { get; set; }
}

public class ThemeDefinition
{
    public string Name { get; set; }
    public string Background { get; set; }
    public string Foreground { get; set; }
    public string Primary { get; set; }
    public string Accent { get; set; }
    public string Muted { get; set; }
    public string Heading { get; set; }
    public string Border { get; set; }
    public string CodeTheme { get; set; }
    public string CodeBackground { get; set; }
    public string CodeForeground { get; set; }
    public string BulletSymbol { get; set; }
    public string BoxDrawingStyle { get; set; }
    public string HeadingStyle { get; set; }
    public string[] ChartPalette { get; set; }
    public string ErrorColor { get; set; }
    public string WarningColor { get; set; }
    public string SuccessColor { get; set; }
    public Hashtable Metadata { get; set; }
}

public class PresentationMetadata
{
    public string Title { get; set; }
    public string Subtitle { get; set; }
    public string Author { get; set; }
    public string Description { get; set; }
    public string Version { get; set; }
    public Hashtable Custom { get; set; }

    public PresentationMetadata()
    {
        Custom = new Hashtable();
    }
}

public class SlideMetadata
{
    public string Author { get; set; }
    public Hashtable Custom { get; set; }

    public SlideMetadata()
    {
        Custom = new Hashtable();
    }
}

public class SlideElement
{
    public string Id { get; set; }
    public string Type { get; set; }
    public object Content { get; set; }
    public string Region { get; set; }
    public int X { get; set; }
    public int Y { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public string Alignment { get; set; }
    public string VerticalAlignment { get; set; }
    public int Padding { get; set; }
    public string ForegroundColor { get; set; }
    public string BackgroundColor { get; set; }
    public bool Border { get; set; }
    public string BorderStyle { get; set; }
    public Hashtable Style { get; set; }
    public int RevealStep { get; set; }
    public string OverflowBehavior { get; set; }
    public Hashtable Properties { get; set; }

    public SlideElement()
    {
        Style = new Hashtable();
        Properties = new Hashtable();
        Alignment = "Left";
        VerticalAlignment = "Top";
        OverflowBehavior = "Wrap";
        Region = "Content";
    }
}

public class Slide
{
    public string Id { get; set; }
    public int Index { get; set; }
    public string Title { get; set; }
    public string Layout { get; set; }
    public List<SlideElement> Elements { get; set; }
    public string Notes { get; set; }
    public string Background { get; set; }
    public string Transition { get; set; }
    public bool Hidden { get; set; }
    public SlideMetadata Metadata { get; set; }
    public int MaxRevealStep { get; set; }

    public Slide()
    {
        Id = Guid.NewGuid().ToString();
        Elements = new List<SlideElement>();
        Metadata = new SlideMetadata();
        Layout = "TitleAndContent";
        Transition = "None";
        Hidden = false;
        MaxRevealStep = 0;
    }
}

public class TerminalPresentation
{
    public string Title { get; set; }
    public string Subtitle { get; set; }
    public string Author { get; set; }
    public string Description { get; set; }
    public string Theme { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public List<Slide> Slides { get; set; }
    public PresentationMetadata Metadata { get; set; }
    public DateTime CreatedDate { get; set; }
    public DateTime ModifiedDate { get; set; }
    public string DefaultTransition { get; set; }
    public string DefaultLayout { get; set; }
    public Hashtable Configuration { get; set; }

    public TerminalPresentation()
    {
        Slides = new List<Slide>();
        Metadata = new PresentationMetadata();
        CreatedDate = DateTime.UtcNow;
        ModifiedDate = DateTime.UtcNow;
        Theme = "Midnight";
        DefaultTransition = "None";
        DefaultLayout = "TitleAndContent";
        Width = 0;
        Height = 0;
        Configuration = new Hashtable();
    }
}
