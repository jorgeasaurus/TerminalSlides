using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.CompilerServices;

[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace TerminalSlides.Schema.V1
{
    internal static class PayloadCollections
    {
        public static IReadOnlyList<T> Snapshot<T>(IReadOnlyList<T> values)
        {
            if (values == null || values.Count == 0)
            {
                return Array.AsReadOnly(Array.Empty<T>());
            }

            var copy = new T[values.Count];
            for (var index = 0; index < values.Count; index++)
            {
                copy[index] = values[index];
            }

            return Array.AsReadOnly(copy);
        }
    }

    public static class MediaOriginRegistry
    {
        private sealed class Origin
        {
            public Origin(string directory) { Directory = directory; }
            public string Directory { get; }
        }

        private static readonly ConditionalWeakTable<SlideElement, Origin> Origins =
            new ConditionalWeakTable<SlideElement, Origin>();

        public static void Set(SlideElement element, string directory)
        {
            if (element == null) throw new ArgumentNullException(nameof(element));
            if (string.IsNullOrWhiteSpace(directory)) throw new ArgumentException("A media-origin directory is required.", nameof(directory));
            Origins.Remove(element);
            Origins.Add(element, new Origin(directory));
        }

        public static string Get(SlideElement element)
        {
            if (element == null) return null;
            Origin origin;
            return Origins.TryGetValue(element, out origin) ? origin.Directory : null;
        }
    }

    public enum ElementKind
    {
        Title,
        Subtitle,
        Text,
        Bullet,
        Code,
        Table,
        Chart,
        Diagram,
        Image,
        Quote,
        Box
    }

    public enum ChartKind
    {
        HorizontalBar,
        Bar,
        Line,
        Sparkline,
        Gauge
    }

    public enum ScalarKind
    {
        Null,
        String,
        Char,
        Boolean,
        SByte,
        Byte,
        Int16,
        UInt16,
        Int32,
        UInt32,
        Int64,
        UInt64,
        Single,
        Double,
        Decimal,
        DateTime,
        DateTimeOffset,
        TimeSpan,
        Guid
    }

    public abstract class ElementPayload { }

    public sealed class TextPayload : ElementPayload
    {
        public TextPayload(string text) { Text = text ?? string.Empty; }
        public string Text { get; }
    }

    public sealed class CodePayload : ElementPayload
    {
        public CodePayload(string code, string language)
        {
            Code = code ?? string.Empty;
            Language = string.IsNullOrWhiteSpace(language) ? "text" : language;
        }

        public string Code { get; }
        public string Language { get; }
    }

    public sealed class ScalarValue
    {
        public ScalarValue(ScalarKind kind, string value)
        {
            Kind = kind;
            Value = value;
        }

        public ScalarKind Kind { get; }
        public string Value { get; }
    }

    public sealed class DataCell
    {
        public DataCell(string name, ScalarValue value)
        {
            if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("A data-cell name is required.", nameof(name));
            Name = name;
            Value = value ?? new ScalarValue(ScalarKind.Null, null);
        }

        public string Name { get; }
        public ScalarValue Value { get; }
    }

    public sealed class DataRow
    {
        public DataRow(IReadOnlyList<DataCell> cells) { Cells = PayloadCollections.Snapshot(cells); }
        public IReadOnlyList<DataCell> Cells { get; }
    }

    public sealed class TablePayload : ElementPayload
    {
        public TablePayload(IReadOnlyList<DataRow> rows) { Rows = PayloadCollections.Snapshot(rows); }
        public IReadOnlyList<DataRow> Rows { get; }
    }

    public sealed class ChartPoint
    {
        public ChartPoint(string label, decimal value)
        {
            Label = label ?? string.Empty;
            Value = value;
        }

        public string Label { get; }
        public decimal Value { get; }
    }

    public sealed class ChartPayload : ElementPayload
    {
        public ChartPayload(IReadOnlyList<ChartPoint> points, ChartKind chartKind, string title)
        {
            Points = PayloadCollections.Snapshot(points);
            ChartKind = chartKind;
            Title = title;
        }

        public IReadOnlyList<ChartPoint> Points { get; }
        public ChartKind ChartKind { get; }
        public string Title { get; }
    }

    public sealed class DiagramNode
    {
        public DiagramNode(string id, string label)
        {
            if (string.IsNullOrWhiteSpace(id)) throw new ArgumentException("A diagram-node id is required.", nameof(id));
            Id = id;
            Label = label ?? string.Empty;
        }

        public string Id { get; }
        public string Label { get; }
    }

    public sealed class DiagramEdge
    {
        public DiagramEdge(string from, string to, string label)
        {
            if (string.IsNullOrWhiteSpace(from)) throw new ArgumentException("A diagram-edge source is required.", nameof(from));
            if (string.IsNullOrWhiteSpace(to)) throw new ArgumentException("A diagram-edge destination is required.", nameof(to));
            From = from;
            To = to;
            Label = label;
        }

        public string From { get; }
        public string To { get; }
        public string Label { get; }
    }

    public sealed class DiagramPayload : ElementPayload
    {
        public DiagramPayload(IReadOnlyList<DiagramNode> nodes, IReadOnlyList<DiagramEdge> edges)
        {
            Nodes = PayloadCollections.Snapshot(nodes);
            Edges = PayloadCollections.Snapshot(edges);
        }

        public IReadOnlyList<DiagramNode> Nodes { get; }
        public IReadOnlyList<DiagramEdge> Edges { get; }
    }

    public sealed class ImagePayload : ElementPayload
    {
        public ImagePayload(string path, string altText)
        {
            if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("An image path is required.", nameof(path));
            Path = path;
            AltText = altText;
        }

        public string Path { get; }
        public string AltText { get; }
    }

    public sealed class QuotePayload : ElementPayload
    {
        public QuotePayload(string text, string attribution)
        {
            Text = text ?? string.Empty;
            Attribution = attribution;
        }

        public string Text { get; }
        public string Attribution { get; }
    }

    public sealed class TerminalCapability
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

    public sealed class ThemeDefinition
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

    public sealed class PresentationMetadata
    {
        public PresentationMetadata() { Custom = new Hashtable(); }
        public string Title { get; set; }
        public string Subtitle { get; set; }
        public string Author { get; set; }
        public string Description { get; set; }
        public string Version { get; set; }
        public Hashtable Custom { get; set; }
    }

    public sealed class SlideMetadata
    {
        public SlideMetadata() { Custom = new Hashtable(); }
        public string Author { get; set; }
        public Hashtable Custom { get; set; }
    }

    public sealed class SlideElement
    {
        public SlideElement(ElementKind kind, ElementPayload payload)
        {
            Kind = kind;
            Payload = payload ?? throw new ArgumentNullException(nameof(payload));
            ValidatePayload(kind, payload);
            Id = Guid.NewGuid().ToString();
            Alignment = "Left";
            VerticalAlignment = "Top";
            BorderStyle = "single";
            OverflowBehavior = "Wrap";
            Region = "Content";
        }

        private static void ValidatePayload(ElementKind kind, ElementPayload payload)
        {
            var valid = false;
            switch (kind)
            {
                case ElementKind.Title:
                case ElementKind.Subtitle:
                case ElementKind.Text:
                case ElementKind.Bullet:
                case ElementKind.Box:
                    valid = payload is TextPayload;
                    break;
                case ElementKind.Code:
                    valid = payload is CodePayload;
                    break;
                case ElementKind.Table:
                    valid = payload is TablePayload;
                    break;
                case ElementKind.Chart:
                    valid = payload is ChartPayload;
                    break;
                case ElementKind.Diagram:
                    valid = payload is DiagramPayload;
                    break;
                case ElementKind.Image:
                    valid = payload is ImagePayload;
                    break;
                case ElementKind.Quote:
                    valid = payload is QuotePayload;
                    break;
            }

            if (!valid)
            {
                throw new ArgumentException(
                    $"Payload type '{payload.GetType().Name}' is not valid for element kind '{kind}'.",
                    nameof(payload));
            }
        }

        public string Id { get; set; }
        public ElementKind Kind { get; }
        public ElementPayload Payload { get; }
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
        public int RevealStep { get; set; }
        public string OverflowBehavior { get; set; }
    }

    public sealed class Slide
    {
        public Slide()
        {
            Id = Guid.NewGuid().ToString();
            Elements = new List<SlideElement>();
            Metadata = new SlideMetadata();
            Layout = "TitleAndContent";
            Transition = "None";
        }

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
    }

    public sealed class TerminalPresentation
    {
        public TerminalPresentation()
        {
            Slides = new List<Slide>();
            Metadata = new PresentationMetadata();
            CreatedDate = DateTime.UtcNow;
            ModifiedDate = DateTime.UtcNow;
            Theme = "Midnight";
            DefaultTransition = "None";
            DefaultLayout = "TitleAndContent";
            Configuration = new Hashtable();
        }

        public string Title { get; set; }
        public string Subtitle { get; set; }
        public string Author { get; set; }
        public string Description { get; set; }
        public string Theme { get; set; }
        public ThemeDefinition EmbeddedTheme { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public List<Slide> Slides { get; set; }
        public PresentationMetadata Metadata { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime ModifiedDate { get; set; }
        public string DefaultTransition { get; set; }
        public string DefaultLayout { get; set; }
        public Hashtable Configuration { get; set; }
    }
}
