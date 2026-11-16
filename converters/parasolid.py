"""Run inside Siemens NX with run_journal. All working files are job-local."""
import json
import os

import NXOpen
import NXOpen.UF


def facet_body(uf, body, params):
    model = uf.Facet.FacetSolid(body.Tag, params)
    positions, normals, indices, faces = [], [], [], []
    vertex_indices = {}
    colors = {}

    for face in body.GetFaces():
        face_id = uf.Facet.AskFaceIdOfSolidFace(model, face.Tag)
        first = len(indices) // 3
        facet = uf.Facet.CycleFacetsInFace(model, face_id, -1)
        while facet != -1:
            count, points = uf.Facet.AskVerticesOfFacet(model, facet)
            normal_count, directions = uf.Facet.AskNormalsOfFacet(model, facet)
            if count != 3 or normal_count != 3:
                raise ValueError("NX returned a non-triangular facet")
            for point, normal in zip(points, directions):
                key = tuple(point) + tuple(normal)
                if key not in vertex_indices:
                    vertex_indices[key] = len(positions) // 3
                    positions.extend(point)
                    normals.extend(normal)
                indices.append(vertex_indices[key])
            facet = uf.Facet.CycleFacetsInFace(model, face_id, facet)

        last = len(indices) // 3 - 1
        if last < first:
            raise ValueError("NX could not triangulate a face")
        if face.Color not in colors:
            _, colors[face.Color] = uf.Disp.AskColor(face.Color, 0)
        faces.append({"first": first, "last": last, "color": colors[face.Color]})

    if not indices or len(indices) // 3 != uf.Facet.AskNFacetsInModel(model):
        raise ValueError("Incomplete body tessellation")
    return {"attributes": {"position": {"array": positions}, "normal": {"array": normals}},
            "index": {"array": indices}, "brep_faces": faces}


def convert():
    session = NXOpen.Session.GetSession()
    part = session.Parts.NewDisplay(os.path.abspath("model.prt"), NXOpen.Part.Units.Millimeters)
    importer = part.ImportManager.CreateParasolidImporter()
    importer.FileName = os.path.abspath("input.x_t")
    importer.Commit()
    importer.Destroy()

    bodies = list(part.Bodies)
    if not bodies:
        raise ValueError("The file contains no solid or sheet bodies")
    uf = NXOpen.UF.UFSession.GetUFSession()
    params = uf.Facet.AskDefaultParameters()
    params.MaxFacetEdges = 3
    params.StoreFaceTags = True
    params.SpecifySurfaceTolerance = params.SpecifyCurveTolerance = True
    params.SurfaceDistTolerance = params.CurveDistTolerance = 0.02  # mm
    params.SurfaceAngularTolerance = params.CurveAngularTolerance = 0.15  # radians
    with open("mesh.tmp", "w") as output:
        output.write('{"meshes":[')
        for index, body in enumerate(bodies):
            if index:
                output.write(",")
            json.dump(facet_body(uf, body, params), output, allow_nan=False, separators=(",", ":"))
        output.write("]}")
    # NX can return success even when a journal fails. Publish only complete geometry.
    os.rename("mesh.tmp", "mesh.json")


if __name__ == "__main__":
    try:
        convert()
    except Exception as error:
        with open("error.txt", "w", encoding="utf-8") as output:
            output.write(str(error))
        raise
