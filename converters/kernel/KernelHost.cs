using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using PK = PLMComponents.Parasolid.PK_.Unsafe;

// Parasolid delegates file IO and memory allocation to its host. Only the input
// selected by Node and numeric schema keys from the runtime directory may be read.
internal unsafe sealed class KernelHost
{
    private delegate void Lifecycle(int* error);
    private delegate void Allocate(int* size, IntPtr* memory, int* error);
    private delegate void Open(int* kind, int* format, byte* name, int* length, int* skipHeader, int* id, int* error);
    private delegate void Read(int* kind, int* id, int* capacity, byte* buffer, int* length, int* error);
    private delegate void Close(int* kind, int* id, int* action, int* error);

    private readonly string input;
    private readonly string schemas;
    private readonly List<Delegate> callbacks = new List<Delegate>();
    private readonly Dictionary<int, FileStream> files = new Dictionary<int, FileStream>();
    private readonly byte[] buffer = new byte[65536];
    private int nextId;

    public KernelHost(string inputFile, string schemaDir)
    {
        input = inputFile;
        schemas = schemaDir;
    }

    private IntPtr Keep(Delegate callback)
    {
        callbacks.Add(callback);
        return Marshal.GetFunctionPointerForDelegate(callback);
    }

    public void Start()
    {
        var handlers = new PK.SESSION.frustrum_v();
        handlers.fstart = Keep(new Lifecycle(error => *error = 0));
        handlers.fstop = Keep(new Lifecycle(error => *error = 0));
        handlers.fmallo = Keep(new Allocate(AllocateMemory));
        handlers.fmfree = Keep(new Allocate(FreeMemory));
        handlers.ffoprd = Keep(new Open(OpenFile));
        handlers.ffread = Keep(new Read(ReadFile));
        handlers.ffclos = Keep(new Close(CloseFile));
        Converter.Check(PK.SESSION._register_frustrum(&handlers), "register host");
        var options = new PK.SESSION.start_o_t(true);
        Converter.Check(PK.SESSION.start(&options), "start session");
    }

    private static void AllocateMemory(int* size, IntPtr* memory, int* error)
    {
        *memory = IntPtr.Zero;
        *error = 15;
        try { *memory = Marshal.AllocHGlobal(*size); *error = 0; }
        catch (OutOfMemoryException) { }
    }

    private static void FreeMemory(int* size, IntPtr* memory, int* error)
    {
        Marshal.FreeHGlobal(*memory);
        *error = 0;
    }

    private static bool SkipHeader(FileStream stream)
    {
        byte[] marker = Encoding.ASCII.GetBytes("**END_OF_HEADER");
        int matched = 0;
        int value;
        while ((value = stream.ReadByte()) >= 0)
        {
            if (value == '\n')
            {
                if (matched == marker.Length) return true;
                matched = 0;
            }
            else if (matched >= 0 && matched < marker.Length)
                matched = value == marker[matched] ? matched + 1 : -1;
        }
        return false;
    }

    private void OpenFile(int* kind, int* format, byte* name, int* length, int* skip, int* id, int* error)
    {
        *id = 0;
        *error = 2;
        FileStream stream = null;
        try
        {
            string key = Marshal.PtrToStringAnsi((IntPtr)name, *length);
            string path;
            if (key == "model") path = input;
            else if (Regex.IsMatch(key, @"\Asch_[0-9]+(?:_[0-9]+)*\z", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
                path = Path.Combine(schemas, key.ToLowerInvariant() + ".sch_txt");
            else return;

            stream = File.OpenRead(path);
            if (*skip != 0 && !SkipHeader(stream)) { *error = 16; return; }
            *id = ++nextId;
            files.Add(*id, stream);
            stream = null;
            *error = 0;
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { *error = 10; }
        finally { if (stream != null) stream.Dispose(); }
    }

    private void ReadFile(int* kind, int* id, int* capacity, byte* dest, int* length, int* error)
    {
        *length = 0;
        *error = 13;
        FileStream file;
        if (!files.TryGetValue(*id, out file)) return;
        try
        {
            int count = file.Read(buffer, 0, Math.Min(*capacity, buffer.Length));
            Marshal.Copy(buffer, 0, (IntPtr)dest, count);
            *length = count;
            *error = count == 0 ? 4 : 0;
        }
        catch (IOException) { }
    }

    private void CloseFile(int* kind, int* id, int* action, int* error)
    {
        FileStream file;
        *error = 14;
        if (!files.TryGetValue(*id, out file)) return;
        file.Dispose();
        files.Remove(*id);
        *error = 0;
    }
}
