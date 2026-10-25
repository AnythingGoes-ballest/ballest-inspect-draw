// Inspect Draw: draw lines in the world while looking around in the game's inspect mode (T while on a track).
// Pick the pencil or the eraser in the menu, then hold the left mouse button: the pencil draws a tube that follows the
// cursor, the eraser takes away the parts of lines it passes over (a line erased through its middle leaves both
// halves). While a tool is on, a see-through layer over the screen takes those clicks, so the camera stays still;
// with neither on, the mouse turns the camera as usual. A ring at the cursor shows the tool's size ([ and ] change
// it). Ctrl+Z undoes and Ctrl+Y redoes (strokes, erases and clears alike), and the number keys pick a colour. The
// small movable menu shows only in inspect mode, and steps aside while the game's pause menu is up.
//
// Strokes are saved per map (by the race's track key) and come back the next time that map is played. The stroke
// itself (the mouse, where its points go, the layer that keeps the camera still, the size ring) is Draw Core's.

import void DrawCore_Frame(bool, bool, bool, int, double, double, double, double, double) from "draw-core";
import int DrawCore_State() from "draw-core";
import int DrawCore_Count() from "draw-core";
import int DrawCore_ChangedFrom() from "draw-core";
import void DrawCore_Point(int, double &out, double &out, double &out) from "draw-core";
import void DrawCore_Cancel() from "draw-core";
import double DrawCore_PixelAngle(float, float) from "draw-core";

const int kPlaceSurface = 0, kPlaceAir = 2;             // Draw Core's placements
const int kStateDrawing = 1, kStateFinished = 2;        // and stroke states

class Stroke
{
    int colour;
    double radius;
    array<double> points;       // x, y, z of each point, one after another
    array<int> tubes;           // the shapes drawing it: a long stroke is cut into pieces of kPieceLength points
    double cx, cy, cz, reach;   // a sphere around it all, for skipping it quickly when erasing

    void Bound()
    {
        uint n = points.length() / 3;
        if (n == 0)
            return;
        double minX = points[0], minY = points[1], minZ = points[2], maxX = minX, maxY = minY, maxZ = minZ;
        for (uint i = 1; i < n; i++)
        {
            double x = points[i * 3], y = points[i * 3 + 1], z = points[i * 3 + 2];
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            if (z < minZ) minZ = z;
            if (z > maxZ) maxZ = z;
        }
        cx = (minX + maxX) / 2;
        cy = (minY + maxY) / 2;
        cz = (minZ + maxZ) / 2;
        double ex = maxX - cx, ey = maxY - cy, ez = maxZ - cz;
        reach = Math::sqrt(ex * ex + ey * ey + ez * ez) + radius;
    }
}

// One step of the history: the strokes it took away and the ones it added. A stroke drawn adds one; a clear takes
// all away; an erase takes away the strokes it cut and adds what was left of them. Undo puts it back the other way.
class Step
{
    array<Stroke@> removed;
    array<Stroke@> added;
}

const int kNoTool = 0, kPencil = 1, kEraser = 2;

const int kPieceLength = 120;           // points per tube: only the growing piece is swept again while drawing
const float kStepPixels = 4;            // the eraser's path is sampled at least this often
const int kMaxEraseSteps = 24;          // eraser samples per frame at most
const float kSizeStep = 0.05f;          // how much [ and ] change the size

const array<string> kColourNames = {"white", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink", "black"};
// number keys pick a colour too: 1 to 9, then 0 for the tenth
const array<Input::Key> kColourKeys = {Input::N1, Input::N2, Input::N3, Input::N4, Input::N5, Input::N6, Input::N7, Input::N8, Input::N9, Input::N0};
const array<float> kColours = {
    1, 1, 1,
    1, 0.03f, 0.03f,
    1, 0.3f, 0,
    1, 0.85f, 0,
    0.1f, 1, 0.05f,
    0, 0.8f, 1,
    0.05f, 0.15f, 1,
    0.5f, 0.05f, 1,
    1, 0.15f, 0.6f,
    0.02f, 0.02f, 0.02f
};

// Grind Stats' card look: the game's menu font on a dark box, lime for what's on
const string kFont = "/Game/UI/Fonts/CocogoosePro.CocogoosePro";
const float BOX_R = 0.08f, BOX_G = 0.08f, BOX_B = 0.09f;
const float BUTTON_R = 0.0232f, BUTTON_G = 0.0273f, BUTTON_B = 0.0382f;     // #2a2e37
const float LIME_R = 0.80f, LIME_G = 1.0f, LIME_B = 0.0f;
const float MUTED_A = 0.65f;            // the labels are white, this opaque
const float kSwatch = 34;               // a colour square, pixels
const float kSlider = 120;

array<Stroke@> strokes;
array<Step@> history;
array<Step@> redoable;          // steps undone, newest last; any new step forgets them
Stroke@ drawing;                // the stroke being drawn, or null
int built = 0;                  // how many of Draw Core's points the stroke being drawn has
float lastMx, lastMy;           // where the cursor was sampled last
Step@ erasing;                  // the erase being made (one per press), or null
array<Stroke@> erasedFrom;      // strokes there before this erase that it has cut
int tool = kPencil;
int colour = 1;
float brushSize = 0.25f;        // 0..1, see Radius()
float eraserSize = 0.3f;        // 0..1, see EraserPixels()
float depth = 0.3f;             // 0..1, see AirDistance()
bool onSurface = true;
bool showLines = true;
bool showWhileDriving = false;
bool shown = true;              // whether the shapes are shown now

string mapKey = "";
int mapNumber = -1;
bool wasInspecting = false;
bool gameMenu = false;          // the game's pause menu is up (measured: its race header shows with it, never in
double gameMenuAt = -1;         // inspect mode itself); looked at a few times a second

UI::Window@ menu;
UI::Button@ pencilButton;
UI::Button@ eraserButton;
array<UI::Button@> swatches;
UI::Text@ colourText;
UI::Text@ sizeLabel;
UI::Text@ sizeText;
UI::Slider@ sizeSlider;
UI::Slider@ depthSlider;
UI::Text@ depthText;
UI::CheckBox@ surfaceBox;
UI::CheckBox@ showBox;
UI::CheckBox@ drivingBox;
UI::Button@ undoButton;
UI::Button@ redoButton;
UI::Button@ clearButton;
UI::Text@ countText;

int ColourIndex(int i) { return i < 0 ? 0 : (i >= int(kColourNames.length()) ? int(kColourNames.length()) - 1 : i); }
float Clamp01(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

double Radius(float t) { return 1 + t * t * 99; }                // cm: 1 to 100
double EraserPixels() { return 6 + eraserSize * eraserSize * 144; }    // 6 to 150
double AirDistance() { return 150 + depth * depth * 4850; }

// ---------------------------------------------------------------- saving

string Format(double v) { return formatFloat(v, "", 0, 1); }

void Save()
{
    if (mapKey == "")
        return;
    string text = "";
    for (uint i = 0; i < strokes.length(); i++)
    {
        Stroke@ s = strokes[i];
        if (i > 0)
            text += "|";
        text += s.colour + "," + Format(s.radius) + ":";
        for (uint p = 0; p < s.points.length(); p++)
            text += (p > 0 ? " " : "") + Format(s.points[p]);
    }
    Storage::Set("strokes:" + mapKey, text);
}

void SaveOptions()
{
    Storage::Set("colour", "" + colour);
    Storage::Set("thickness", formatFloat(brushSize, "", 0, 3));
    Storage::Set("eraser", formatFloat(eraserSize, "", 0, 3));
    Storage::Set("depth", formatFloat(depth, "", 0, 3));
    Storage::Set("surface", onSurface ? "true" : "false");
    Storage::Set("show", showLines ? "true" : "false");
    Storage::Set("driving", showWhileDriving ? "true" : "false");
    Storage::Set("tool", "" + tool);
}

void LoadOptions()
{
    colour = ColourIndex(parseInt(Storage::Get("colour", "1")));
    brushSize = Clamp01(float(parseFloat(Storage::Get("thickness", "0.25"))));
    eraserSize = Clamp01(float(parseFloat(Storage::Get("eraser", "0.3"))));
    depth = Clamp01(float(parseFloat(Storage::Get("depth", "0.3"))));
    onSurface = Storage::Get("surface", "true") == "true";
    showLines = Storage::Get("show", "true") == "true";
    showWhileDriving = Storage::Get("driving", "false") == "true";
    // (0.1 saved the pencil as "pencil=true|false")
    tool = parseInt(Storage::Get("tool", Storage::Get("pencil", "true") == "true" ? "1" : "0"));
    if (tool < kNoTool || tool > kEraser)
        tool = kPencil;
}

void Load()
{
    strokes.resize(0);
    history.resize(0);
    redoable.resize(0);
    @drawing = null;
    @erasing = null;
    if (mapKey == "")
        return;
    string text = Storage::Get("strokes:" + mapKey, "");
    if (text == "")
        return;
    array<string>@ parts = text.split("|");
    for (uint i = 0; i < parts.length(); i++)
    {
        int colon = parts[i].findFirst(":");
        if (colon < 0)
            continue;
        array<string>@ head = parts[i].substr(0, colon).split(",");
        array<string>@ nums = parts[i].substr(colon + 1).split(" ");
        if (head.length() < 2 || nums.length() < 6)
            continue;
        Stroke s;
        s.colour = ColourIndex(parseInt(head[0]));
        s.radius = parseFloat(head[1]);
        for (uint n = 0; n + 2 < nums.length(); n += 3)
        {
            s.points.insertLast(parseFloat(nums[n]));
            s.points.insertLast(parseFloat(nums[n + 1]));
            s.points.insertLast(parseFloat(nums[n + 2]));
        }
        s.Bound();
        Build(s);
        strokes.insertLast(s);
        Step step;                      // a saved stroke can be taken back like a new one
        step.added.insertLast(s);
        history.insertLast(step);
    }
}

// ---------------------------------------------------------------- shapes

// The points of piece `k` of a stroke; each piece starts at the last point of the one before, so they join up.
array<double>@ Piece(Stroke@ s, int k)
{
    int count = int(s.points.length()) / 3;
    int first = k * (kPieceLength - 1);
    int last = first + kPieceLength < count ? first + kPieceLength : count;
    array<double> path;
    for (int i = first; i < last; i++)
        for (int c = 0; c < 3; c++)
            path.insertLast(s.points[i * 3 + c]);
    return path;
}

int Pieces(Stroke@ s)
{
    int count = int(s.points.length()) / 3;
    if (count < 2)
        return 0;
    return (count - 2) / (kPieceLength - 1) + 1;
}

int MakeTube(Stroke@ s, array<double>@ path)
{
    int c = s.colour * 3;
    int id = Draw::Tube(path, s.radius, kColours[c], kColours[c + 1], kColours[c + 2], true);
    if (id != 0)
    {
        Draw::Glow(id, kColours[c], kColours[c + 1], kColours[c + 2], s.colour == 9 ? 0 : 3);
        Draw::Show(id, shown);
    }
    return id;
}

void Build(Stroke@ s)
{
    int pieces = Pieces(s);
    for (int k = 0; k < pieces; k++)
        s.tubes.insertLast(MakeTube(s, Piece(s, k)));
}

// The growing end of the stroke being drawn: the last piece swept again, or a new piece once it's full. A piece too
// short to sweep yet (Draw::Tube gives 0) is made on a later point instead.
void Grow(Stroke@ s)
{
    int pieces = Pieces(s);
    if (pieces == 0)
        return;
    array<double>@ path = Piece(s, pieces - 1);
    if (int(s.tubes.length()) < pieces)
        s.tubes.insertLast(MakeTube(s, path));
    else if (s.tubes[pieces - 1] == 0)
        s.tubes[pieces - 1] = MakeTube(s, path);
    else
        Draw::Retube(s.tubes[pieces - 1], path, s.radius);
}

void Remove(Stroke@ s)
{
    for (uint i = 0; i < s.tubes.length(); i++)
        if (s.tubes[i] != 0)
            Draw::Remove(s.tubes[i]);
    s.tubes.resize(0);
}

void ShowAll(bool on)
{
    shown = on;
    for (uint i = 0; i < strokes.length(); i++)
        for (uint t = 0; t < strokes[i].tubes.length(); t++)
            if (strokes[i].tubes[t] != 0)
                Draw::Show(strokes[i].tubes[t], on);
}

// ---------------------------------------------------------------- history

void Take(Stroke@ s)
{
    int at = strokes.findByRef(s);
    if (at < 0)
        return;
    Remove(s);
    strokes.removeAt(at);
}

void Put(Stroke@ s)
{
    Build(s);
    strokes.insertLast(s);
}

void Push(Step@ step)
{
    history.insertLast(step);
    redoable.resize(0);
    Save();
}

void Undo()
{
    if (history.length() == 0)
        return;
    Step@ step = history[history.length() - 1];
    history.removeLast();
    for (uint i = 0; i < step.added.length(); i++)
        Take(step.added[i]);
    for (uint i = 0; i < step.removed.length(); i++)
        Put(step.removed[i]);
    redoable.insertLast(step);
    Save();
}

void Redo()
{
    if (redoable.length() == 0)
        return;
    Step@ step = redoable[redoable.length() - 1];
    redoable.removeLast();
    for (uint i = 0; i < step.removed.length(); i++)
        Take(step.removed[i]);
    for (uint i = 0; i < step.added.length(); i++)
        Put(step.added[i]);
    history.insertLast(step);
    Save();
}

void ClearAll()
{
    if (strokes.length() == 0)
        return;
    Step step;
    while (strokes.length() > 0)
    {
        Stroke@ s = strokes[strokes.length() - 1];
        Take(s);
        step.removed.insertLast(s);
    }
    Push(step);
}

// ---------------------------------------------------------------- drawing

// The stroke being drawn follows Draw Core's points: new ones are added to its growing end; when Draw Core lays
// earlier points again (a line meeting a surface after a gap), the stroke is built again from all of them.
void FollowStroke()
{
    int st = DrawCore_State();
    if (st != kStateDrawing && st != kStateFinished)
    {
        if (drawing !is null)
        {
            Remove(drawing);            // dropped (Ctrl+Z while drawing, or too short)
            @drawing = null;
        }
        return;
    }
    if (drawing is null)
    {
        @drawing = Stroke();
        drawing.colour = colour;
        drawing.radius = Radius(brushSize);
        built = 0;
    }
    int n = DrawCore_Count();
    int changed = DrawCore_ChangedFrom();
    if (changed < built)
    {
        drawing.points.resize(0);
        built = 0;
        Remove(drawing);
    }
    for (int i = built; i < n; i++)
    {
        double x, y, z;
        DrawCore_Point(i, x, y, z);
        drawing.points.insertLast(x);
        drawing.points.insertLast(y);
        drawing.points.insertLast(z);
    }
    if (n != built || drawing.tubes.length() == 0)
    {
        if (drawing.tubes.length() == 0)
            Build(drawing);
        else
            Grow(drawing);
        built = n;
    }
    if (st == kStateFinished)
        EndStroke();
}

// The stroke being drawn is kept if it has a line's worth of points.
void EndStroke()
{
    if (drawing is null)
        return;
    if (drawing.points.length() >= 6)
    {
        drawing.Bound();
        strokes.insertLast(drawing);
        Step step;
        step.added.insertLast(drawing);
        Push(step);
    }
    else
        Remove(drawing);
    @drawing = null;
    built = 0;
}

// ---------------------------------------------------------------- erasing
//
// The eraser works on what is under it on screen, as Blender's eraser does (a radius in pixels): a point of a line is
// erased when it shows within the eraser's circle, front or back. Measured as an angle from the cursor's ray, so it
// costs no calls into the game per point; lines whose bounding sphere is nowhere near the ray are skipped whole.

// True if (x, y, z) is within `tanA` (and `pad` cm) of the ray from (ox..) along (dx..), in front of it.
bool NearRay(double x, double y, double z, double ox, double oy, double oz, double dx, double dy, double dz, double tanA, double pad)
{
    double vx = x - ox, vy = y - oy, vz = z - oz;
    double t = vx * dx + vy * dy + vz * dz;
    if (t <= 0)
        return false;
    double px = vx - dx * t, py = vy - dy * t, pz = vz - dz * t;
    double limit = t * tanA + pad;
    return px * px + py * py + pz * pz <= limit * limit;
}

// The kept runs of a stroke whose points `cut` are erased, as new strokes of the same colour and size.
void Split(Stroke@ s, array<bool>@ cut)
{
    uint n = s.points.length() / 3;
    uint i = 0;
    while (i < n)
    {
        while (i < n && cut[i])
            i++;
        uint first = i;
        while (i < n && !cut[i])
            i++;
        if (i - first < 2)
            continue;
        Stroke part;
        part.colour = s.colour;
        part.radius = s.radius;
        for (uint k = first * 3; k < i * 3; k++)
            part.points.insertLast(s.points[k]);
        part.Bound();
        Put(part);
        erasing.added.insertLast(part);
    }
}

// Erases what shows within the eraser at (sx, sy).
void EraseAt(float sx, float sy, double tanA)
{
    double ox, oy, oz, dx, dy, dz;
    if (!Camera::Deproject(sx, sy, ox, oy, oz, dx, dy, dz))
        return;
    for (int i = int(strokes.length()) - 1; i >= 0; i--)
    {
        Stroke@ s = strokes[i];
        if (!NearRay(s.cx, s.cy, s.cz, ox, oy, oz, dx, dy, dz, tanA, s.reach))
            continue;
        uint n = s.points.length() / 3;
        array<bool> cut(n, false);
        bool any = false;
        for (uint p = 0; p < n; p++)
            if (NearRay(s.points[p * 3], s.points[p * 3 + 1], s.points[p * 3 + 2], ox, oy, oz, dx, dy, dz, tanA, s.radius))
            {
                cut[p] = true;
                any = true;
            }
        if (!any)
            continue;
        Take(s);
        // a part made earlier in this erase just goes; a stroke from before it is remembered, for undo
        int made = erasing.added.findByRef(s);
        if (made >= 0)
            erasing.added.removeAt(made);
        else
            erasing.removed.insertLast(s);
        Split(s, cut);
    }
}

void Erase()
{
    float mx, my;
    if (erasing is null)
    {
        if (!Input::Pressed(Input::MouseLeft) || menu.hovered || Input::Down(Input::Ctrl) || !Input::MousePosition(mx, my))
            return;
        @erasing = Step();
        lastMx = mx;
        lastMy = my;
        double tanA = DrawCore_PixelAngle(mx, my) * EraserPixels();
        if (tanA > 0)
            EraseAt(mx, my, tanA);
        return;
    }
    if (!Input::Down(Input::MouseLeft))
    {
        EndErase();
        return;
    }
    if (!Input::MousePosition(mx, my))
        return;
    float ex = mx - lastMx, ey = my - lastMy;
    float moved = float(Math::sqrt(ex * ex + ey * ey));
    if (moved < 1)
        return;
    double tanA = DrawCore_PixelAngle(mx, my) * EraserPixels();
    if (tanA <= 0)
        return;
    float stride = float(EraserPixels() / 2) > kStepPixels ? float(EraserPixels() / 2) : kStepPixels;
    int steps = int(Math::ceil(moved / stride));
    if (steps > kMaxEraseSteps)
        steps = kMaxEraseSteps;
    for (int k = 1; k <= steps; k++)
        EraseAt(lastMx + ex * k / steps, lastMy + ey * k / steps, tanA);
    lastMx = mx;
    lastMy = my;
}

// One erase (a press) is one step of the history, if it erased anything.
void EndErase()
{
    if (erasing is null)
        return;
    if (erasing.removed.length() > 0)
        Push(erasing);
    @erasing = null;
}

// ---------------------------------------------------------------- menu

UI::Text@ Label(const string &in text, float size = 15)
{
    UI::Text@ t = menu.AddText(text, size);
    t.SetColor(1, 1, 1, MUTED_A);
    return t;
}

UI::Button@ PlainButton(const string &in label)
{
    UI::Button@ b = menu.AddButton(label);
    b.SetCornerRadius(6);
    b.SetBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1);
    return b;
}

UI::Button@ ToolButton(const string &in picture)
{
    UI::Button@ b = menu.AddIconButton(Plugins::Folder() + picture);
    b.SetSize(36, 36);
    b.SetCornerRadius(8);
    return b;
}

void BuildMenu()
{
    @menu = UI::CreateWindow();
    menu.SetAnchor(1, 0);
    menu.SetPivot(1, 0);
    menu.SetOffset(-40, 110);
    menu.SetBackground(BOX_R, BOX_G, BOX_B, 0.9f);
    menu.SetCornerRadius(10);
    menu.SetPadding(14, 10);
    menu.SetRowGap(6);
    menu.SetFont(kFont, "Regular");
    menu.SetBlocksClicks(true);
    menu.zOrder = 120;

    @pencilButton = ToolButton("pencil.png");
    @eraserButton = ToolButton("eraser.png");
    menu.AddText("inspect draw", 19).SetGapBefore(10);
    menu.AddSpace(0);
    @countText = Label("", 14);
    menu.NewRow();
    for (uint i = 0; i < kColourNames.length(); i++)
    {
        UI::Button@ b = menu.AddIconButton("");
        b.SetSize(kSwatch, kSwatch);
        b.SetCornerRadius(6);
        swatches.insertLast(b);
        if (i == 4)
            menu.NewRow();
    }
    menu.NewRow();
    @colourText = Label("", 14);
    menu.NewRow();
    @sizeLabel = Label("brush size");
    @sizeText = menu.AddText("", 15);
    menu.AddSpace(0);
    @sizeSlider = menu.AddSlider(kSlider);
    menu.NewRow();
    @surfaceBox = menu.AddCheckBox("draw on surfaces", 15);
    menu.NewRow();
    @depthText = Label("air distance");
    menu.AddSpace(0);
    @depthSlider = menu.AddSlider(kSlider);
    menu.NewRow();
    @showBox = menu.AddCheckBox("show lines", 15);
    menu.NewRow();
    @drivingBox = menu.AddCheckBox("show while driving", 15);
    menu.NewRow();
    @undoButton = PlainButton("undo");
    @redoButton = PlainButton("redo");
    menu.AddSpace(0);
    @clearButton = PlainButton("clear all");
    menu.movable = true;                // after SetOffset: that is where "reset position" puts it back
    menu.visible = false;
    RefreshMenu();
}

void ToolLook(UI::Button@ b, bool on)
{
    if (on)
    {
        b.SetBackground(LIME_R, LIME_G, LIME_B, 1);
        b.SetTextColor(0.02f, 0.02f, 0.02f, 1);
    }
    else
    {
        b.SetBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1);
        b.SetTextColor(1, 1, 1, 0.55f);
    }
}

float ToolSize() { return tool == kEraser ? eraserSize : brushSize; }

void ShowSize()
{
    if (tool == kEraser)
        sizeText.text = formatFloat(EraserPixels(), "", 0, 0) + " px";
    else
        sizeText.text = formatFloat(Radius(brushSize) * 2, "", 0, 0) + " cm";
}

void RefreshMenu()
{
    ToolLook(pencilButton, tool == kPencil);
    ToolLook(eraserButton, tool == kEraser);
    for (uint i = 0; i < swatches.length(); i++)
    {
        float a = int(i) == colour ? 1.0f : 0.3f;
        swatches[i].SetBackground(kColours[i * 3], kColours[i * 3 + 1], kColours[i * 3 + 2], a);
    }
    colourText.text = kColourNames[colour] + "   (keys 1-0)";
    sizeLabel.text = tool == kEraser ? "eraser size" : "brush size";
    sizeSlider.value = ToolSize();
    ShowSize();
    depthSlider.value = depth;
    surfaceBox.checked = onSurface;
    showBox.checked = showLines;
    drivingBox.checked = showWhileDriving;
}

void SetSize(float v)
{
    v = Clamp01(v);
    if (tool == kEraser)
        eraserSize = v;
    else
        brushSize = v;
    ShowSize();
}

void ReadMenu()
{
    bool changed = false;
    if (pencilButton.Clicked())
    {
        tool = tool == kPencil ? kNoTool : kPencil;
        changed = true;
        RefreshMenu();
    }
    if (eraserButton.Clicked())
    {
        tool = tool == kEraser ? kNoTool : kEraser;
        changed = true;
        RefreshMenu();
    }
    for (uint i = 0; i < swatches.length(); i++)
    {
        bool picked = swatches[i].Clicked() || (Input::Pressed(kColourKeys[i]) && !Input::Down(Input::Ctrl));
        if (picked && int(i) != colour)
        {
            colour = i;
            changed = true;
            RefreshMenu();
        }
    }
    if (sizeSlider.dragging || Math::abs(sizeSlider.value - ToolSize()) > 0.0001f)
    {
        SetSize(sizeSlider.value);
        changed = true;
    }
    if (Input::Pressed(Input::LeftBracket) || Input::Pressed(Input::RightBracket))
    {
        SetSize(ToolSize() + (Input::Pressed(Input::RightBracket) ? kSizeStep : -kSizeStep));
        sizeSlider.value = ToolSize();
        changed = true;
    }
    if (depthSlider.dragging || Math::abs(depthSlider.value - depth) > 0.0001f)
    {
        depth = depthSlider.value;
        changed = true;
    }
    if (surfaceBox.Changed())
    {
        onSurface = surfaceBox.checked;
        changed = true;
    }
    if (showBox.Changed())
    {
        showLines = showBox.checked;
        changed = true;
    }
    if (drivingBox.Changed())
    {
        showWhileDriving = drivingBox.checked;
        changed = true;
    }
    if (undoButton.Clicked())
        Undo();
    if (redoButton.Clicked())
        Redo();
    if (clearButton.Clicked())
        ClearAll();
    if (changed)
        SaveOptions();
    depthText.text = onSurface ? "distance over sky" : "air distance";
    countText.text = strokes.length() == 1 ? "1 line" : strokes.length() + " lines";
}

// ---------------------------------------------------------------- frame

void Main()
{
    LoadOptions();
    BuildMenu();
}

void Update(float dt)
{
    // a new map: the host has already removed the shapes; the strokes saved for it come back once its key is known
    if (Host::MapNumber() != mapNumber)
    {
        mapNumber = Host::MapNumber();
        mapKey = "";
        strokes.resize(0);
        history.resize(0);
        redoable.resize(0);
        @drawing = null;
        @erasing = null;
    }
    if (mapKey == "" && Race::OnTrack())
    {
        mapKey = Race::TrackKey();
        if (mapKey != "")
            Load();
    }

    bool inspecting = Race::OnTrack() && Camera::Inspecting();
    if (inspecting != wasInspecting)
    {
        wasInspecting = inspecting;
        Log::Info(inspecting ? "inspect mode: menu shown" : "inspect mode ended: menu hidden");
        UI::SetCursorVisible(inspecting);
        if (inspecting)
            RefreshMenu();
    }

    bool wantShown = showLines && (inspecting || showWhileDriving);
    if (wantShown != shown)
        ShowAll(wantShown);

    // the game's pause menu (Esc while inspecting) is the game's: the menu, the click layer and the ring step aside.
    // It doesn't pause the game (Race::IsPaused stays false), so it is seen by the race header it shows.
    if (!inspecting)
        gameMenu = false;
    else if (Host::Time() - gameMenuAt > 0.15 || Host::Time() < gameMenuAt)
    {
        gameMenuAt = Host::Time();
        gameMenu = false;
        array<string>@ parts = Hud::Elements();
        for (uint i = 0; i < parts.length(); i++)
            if (Hud::Name(parts[i]) == "WBP_Header" && Hud::Shown(parts[i]))
                gameMenu = true;
    }
    bool active = inspecting && !gameMenu;
    menu.visible = active;
    if (!inspecting)
    {
        EndErase();
        if (drawing !is null)
            EndStroke();                // inspect mode ended mid-stroke: keep what was drawn
        return;
    }

    if (active)
        ReadMenu();
    bool undoKey = active && Input::Down(Input::Ctrl) && Input::Pressed(Input::Z) && !Input::Down(Input::Shift);
    bool redoKey = active && Input::Down(Input::Ctrl) && (Input::Pressed(Input::Y) || (Input::Pressed(Input::Z) && Input::Down(Input::Shift)));
    if (undoKey && drawing !is null)
    {
        DrawCore_Cancel();              // Ctrl+Z while drawing drops the line being drawn
        undoKey = false;
    }

    bool pencil = tool == kPencil && showLines;
    bool enabled = active && (pencil || tool == kEraser);
    double r = Radius(brushSize);
    DrawCore_Frame(enabled, pencil, menu.hovered, onSurface ? kPlaceSurface : kPlaceAir, 0, r, r > 3 ? r : 3,
                   AirDistance(), tool == kEraser ? EraserPixels() : 0);
    FollowStroke();

    if (redoKey)
        Redo();
    else if (undoKey)
        Undo();
    if (active && tool == kEraser)
        Erase();
    else
        EndErase();
}
