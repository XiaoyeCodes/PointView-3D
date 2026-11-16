using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using PK = PLMComponents.Parasolid.PK_.Unsafe;

internal unsafe class Converter
{
    internal static void Check(PK.ERROR.code_t code, string operation)
    {
        if (code != PK.ERROR.code_t.no_errors) throw new InvalidDataException(operation + ": " + code);
    }

    private readonly TextWriter output;
    private readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue };
    private readonly PK.ATTDEF_t colorDefinition;
    private int bodies;

    private Converter(TextWriter writer)
    {
        output = writer;
        PK.ATTDEF_t definition;
        Check(PK.ATTDEF.find("SDL/TYSA_COLOUR", &definition), "find RGB attribute");
        colorDefinition = definition;
    }

    private double[] Color(PK.ENTITY_t entity)
    {
        if ((int)colorDefinition == 0) return null;
        int count;
        PK.ATTRIB_t* attributes;
        Check(PK.ENTITY.ask_attribs(entity, colorDefinition, &count, &attributes), "read colors");
        try
        {
            if (count == 0) return null;
            int channels;
            double* rgb;
            Check(PK.ATTRIB.ask_doubles(attributes[0], 0, &channels, &rgb), "read RGB");
            try { return channels >= 3 ? new[] { rgb[0], rgb[1], rgb[2] } : null; }
            finally { if (rgb != null) PK.MEMORY.free(rgb); }
        }
        finally { if (attributes != null) PK.MEMORY.free(attributes); }
    }

    private void WritePart(PK.PART_t part, PK.TRANSF_t placement)
    {
        PK.CLASS_t kind;
        Check(PK.ENTITY.ask_class(part, &kind), "read part type");
        if (kind == PK.CLASS_t.body)
        {
            WriteBody(part, placement);
            return;
        }
        if (kind != PK.CLASS_t.assembly) throw new InvalidDataException("Unexpected part type: " + kind);
        int count;
        PK.INSTANCE_t* instances;
        Check(PK.ASSEMBLY.ask_instances(part, &count, &instances), "read assembly");
        try
        {
            for (int i = 0; i < count; i++)
            {
                PK.INSTANCE_sf_t instance;
                Check(PK.INSTANCE.ask(instances[i], &instance), "read instance");
                PK.TRANSF_t transform = instance.transf;
                if ((int)transform == 0) transform = placement;
                else if ((int)placement != 0)
                    Check(PK.TRANSF.transform(instance.transf, placement, &transform), "compose placement");
                WritePart(instance.part, transform);
            }
        }
        finally { if (instances != null) PK.MEMORY.free(instances); }
    }

    private void WriteBody(PK.BODY_t body, PK.TRANSF_t placement)
    {
        int count;
        PK.FACE_t* faces;
        Check(PK.BODY.ask_faces(body, &count, &faces), "read faces");
        try
        {
            if (count == 0) return; // Wire and point bodies have no surface to preview.
            var options = new PK.TOPOL.facet_2_o_t(true);
            options.control.max_facet_sides = 3;
            options.control.is_curve_chord_tol = options.control.is_surface_plane_tol = true;
            options.control.curve_chord_tol = options.control.surface_plane_tol = 0.00002; // metres
            options.control.is_curve_chord_ang = options.control.is_surface_plane_ang = true;
            options.control.curve_chord_ang = options.control.surface_plane_ang = 0.15;
            options.choice.facet_fin = options.choice.fin_data = options.choice.facet_face = true;
            options.choice.data_point_idx = options.choice.point_vec = true;
            options.choice.data_normal_idx = options.choice.normal_vec = true;
            PK.TOPOL_t topology = body;
            PK.TOPOL.facet_2_r_t result;
            Check(PK.TOPOL.facet_2(1, &topology, (int)placement == 0 ? null : &placement, &options, &result), "tessellate");
            try
            {
                if (bodies++ > 0) output.Write(",");
                output.Write(json.Serialize(BuildMesh(body, faces, count, result)));
            }
            finally { PK.TOPOL.facet_2_r_f(&result); }
        }
        finally { if (faces != null) PK.MEMORY.free(faces); }
    }

    private object BuildMesh(PK.BODY_t body, PK.FACE_t* faces, int faceCount, PK.TOPOL.facet_2_r_t result)
    {
        var tables = new Dictionary<PK.TOPOL.fctab_t, PK.TOPOL.facet_table_subunion001_t>();
        for (int i = 0; i < result.number_of_tables; i++)
            tables.Add(result.tables[i].fctab, result.tables[i].table);

        var facetFins = tables[PK.TOPOL.fctab_t.facet_fin_c].facet_fin;
        var finData = tables[PK.TOPOL.fctab_t.fin_data_c].fin_data;
        var facetFaces = tables[PK.TOPOL.fctab_t.facet_face_c].facet_face;
        var pointIndices = tables[PK.TOPOL.fctab_t.data_point_c].data_point_idx;
        var normalIndices = tables[PK.TOPOL.fctab_t.data_normal_c].data_normal_idx;
        var points = tables[PK.TOPOL.fctab_t.point_vec_c].point_vec;
        var normals = tables[PK.TOPOL.fctab_t.normal_vec_c].normal_vec;

        int vertexCount = pointIndices->length;
        var positions = new double[vertexCount * 3];
        var directions = new double[vertexCount * 3];
        if (normalIndices->length != vertexCount || facetFins->length != result.number_of_facets * 3)
            throw new InvalidDataException("Incomplete tessellation tables");
        for (int i = 0; i < vertexCount; i++)
        {
            for (int axis = 0; axis < 3; axis++)
            {
                positions[i * 3 + axis] = points->vec[pointIndices->point[i]].coord[axis] * 1000;
                directions[i * 3 + axis] = normals->vec[normalIndices->normal[i]].coord[axis];
            }
        }

        var corners = new int[result.number_of_facets * 3];
        var used = new byte[result.number_of_facets];
        for (int i = 0; i < facetFins->length; i++)
        {
            var pair = facetFins->data[i];
            if (used[pair.facet] >= 3) throw new InvalidDataException("Unexpected polygon");
            corners[3 * pair.facet + used[pair.facet]++] = finData->data[pair.fin];
        }
        var triangles = new Dictionary<int, List<int>>();
        for (int i = 0; i < result.number_of_facets; i++)
        {
            if (used[i] != 3) throw new InvalidDataException("Incomplete triangle");
            int face = facetFaces->face[i];
            List<int> group;
            if (!triangles.TryGetValue(face, out group)) triangles.Add(face, group = new List<int>());
            group.Add(corners[3 * i]);
            group.Add(corners[3 * i + 1]);
            group.Add(corners[3 * i + 2]);
        }
        var indices = new List<int>(corners.Length);
        var groups = new List<object>(faceCount);
        for (int i = 0; i < faceCount; i++)
        {
            List<int> group;
            if (!triangles.TryGetValue(faces[i], out group)) throw new InvalidDataException("A face has no facets");
            int first = indices.Count / 3;
            indices.AddRange(group);
            groups.Add(new { first, last = indices.Count / 3 - 1, color = Color(faces[i]) });
        }
        return new { attributes = new { position = new { array = positions }, normal = new { array = directions } },
            index = new { array = indices }, brep_faces = groups, color = Color(body) };
    }

    private static void Convert(string input, string output)
    {
        var host = new KernelHost(input, Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "schemas"));
        host.Start();
        try
        {
            var options = new PK.PART.receive_o_t(true);
            options.transmit_format = PK.transmit_format_t.text_c;
            int count;
            PK.PART_t* parts;
            Check(PK.PART.receive("model", &options, &count, &parts), "read X_T");
            using (var writer = new StreamWriter(output, false, new UTF8Encoding(false)))
            {
                var converter = new Converter(writer);
                writer.Write("{\"meshes\":[");
                for (int i = 0; i < count; i++) converter.WritePart(parts[i], PK.TRANSF_t.@null);
                if (converter.bodies == 0) throw new InvalidDataException("No surfaces in file");
                writer.Write("]}");
            }
        }
        finally { PK.SESSION.stop(); GC.KeepAlive(host); }
    }

    public static int Main(string[] args)
    {
        try { Convert(args[0], args[1]); return 0; }
        catch (Exception error) { Console.Error.WriteLine(error.Message); return 1; }
    }
}
