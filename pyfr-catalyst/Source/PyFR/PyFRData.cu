#include "PyFRData.h"

#include <algorithm>
#include <cassert>
#include <iostream>
#include <iterator>
#include <limits>
#include <sstream>
#include <stdexcept>

#include <vtkm/CellShape.h>
#include <vtkm/TopologyElementTag.h>
#include <vtkm/cont/CellSetSingleType.h>
#include <vtkm/cont/CoordinateSystem.h>
#include <vtkm/cont/DeviceAdapter.h>
#include <vtkm/cont/DataSet.h>
#include <vtkm/cont/Field.h>
#include <vtkm/cont/cuda/DeviceAdapterCuda.h>

#include "ArrayHandleExposed.h"

PyFRData::PyFRData() : catalystData(NULL)
{

}

//------------------------------------------------------------------------------
PyFRData::~PyFRData()
{
}

//------------------------------------------------------------------------------
void PyFRData::Init(void* data)
{
  this->catalystData = static_cast<struct CatalystData*>(data);

  // we only take data from the first stored cell type (i.e. hexahedra)
  MeshDataForCellType* meshData = &(this->catalystData->meshData[0]);
  SolutionDataForCellType* solutionData =
    &(this->catalystData->solutionData[0]);

  typedef ::vtkm::cont::DeviceAdapterTagCuda CudaTag;

  Vec3ArrayHandle vertices;
    {
    const vtkm::Vec<FPType,3> *vecData =
      reinterpret_cast<const vtkm::Vec<FPType,3>*>(meshData->vertices);
    typedef vtkm::cont::internal::Storage<vtkm::Vec<FPType,3>,
                                       vtkm::cont::StorageTagBasic> Vec3Storage;
    Vec3ArrayHandle tmp =
      Vec3ArrayHandle(Vec3Storage(vecData,
                                  meshData->nCells*meshData->nVerticesPerCell));
    vtkm::cont::DeviceAdapterAlgorithm<CudaTag>().
      Copy(tmp, vertices);
    }

  vtkm::cont::ArrayHandle<vtkm::Id> connectivity;
    {
    vtkm::cont::ArrayHandle<int32_t> tmp =
      vtkm::cont::make_ArrayHandle(meshData->con,(meshData->nCells*
                                                  meshData->nVerticesPerCell));
    vtkm::cont::ArrayHandleCast<vtkm::Id,
      vtkm::cont::ArrayHandle<int32_t> > cast(tmp);
    vtkm::cont::DeviceAdapterAlgorithm<CudaTag>().
      Copy(cast, connectivity);
    }

  vtkm::cont::CellSetSingleType<> cset(vtkm::CellShapeTagHexahedron(), "cells");
  cset.Fill(connectivity);

  StridedDataFunctor stridedDataFunctor[5];
  for (unsigned i=0;i<5;i++)
    {
    stridedDataFunctor[i].NumberOfCells = meshData->nCells;
    stridedDataFunctor[i].NVerticesPerCell = meshData->nVerticesPerCell;
    stridedDataFunctor[i].NSolutionTypes = 5;
    stridedDataFunctor[i].SolutionType = i;
    stridedDataFunctor[i].CellStride = solutionData->lsdim;
    stridedDataFunctor[i].VertexStride = solutionData->ldim;
    }

  RawDataArrayHandle rawSolutionArray = vtkm::cont::cuda::make_ArrayHandle(
    static_cast<FPType*>(solutionData->solution),
    solutionData->ldim*meshData->nVerticesPerCell);

  DataIndexArrayHandle densityIndexArray(stridedDataFunctor[0],
                                   meshData->nCells*meshData->nVerticesPerCell);
  ScalarDataArrayHandle densityArray(densityIndexArray, rawSolutionArray);

  DataIndexArrayHandle velocity_uIndexArray(stridedDataFunctor[1],
                                   meshData->nCells*meshData->nVerticesPerCell);
  ScalarDataArrayHandle velocity_uArray(velocity_uIndexArray, rawSolutionArray);

  DataIndexArrayHandle velocity_vIndexArray(stridedDataFunctor[2],
                                   meshData->nCells*meshData->nVerticesPerCell);
  ScalarDataArrayHandle velocity_vArray(velocity_vIndexArray, rawSolutionArray);

  DataIndexArrayHandle velocity_wIndexArray(stridedDataFunctor[3],
                                   meshData->nCells*meshData->nVerticesPerCell);
  ScalarDataArrayHandle velocity_wArray(velocity_wIndexArray, rawSolutionArray);

  DataIndexArrayHandle pressureIndexArray(stridedDataFunctor[4],
                                   meshData->nCells*meshData->nVerticesPerCell);
  ScalarDataArrayHandle pressureArray(pressureIndexArray, rawSolutionArray);

  enum ElemType { CONSTANT=0, LINEAR=1, QUADRATIC=2 };
  vtkm::cont::Field density("density",LINEAR,vtkm::cont::Field::ASSOC_POINTS,vtkm::cont::DynamicArrayHandle(densityArray));
  vtkm::cont::Field velocity_u("velocity_u",LINEAR,vtkm::cont::Field::ASSOC_POINTS,vtkm::cont::DynamicArrayHandle(velocity_uArray));
  vtkm::cont::Field velocity_v("velocity_v",LINEAR,vtkm::cont::Field::ASSOC_POINTS,vtkm::cont::DynamicArrayHandle(velocity_vArray));
  vtkm::cont::Field velocity_w("velocity_w",LINEAR,vtkm::cont::Field::ASSOC_POINTS,vtkm::cont::DynamicArrayHandle(velocity_wArray));
  vtkm::cont::Field pressure("pressure",LINEAR,vtkm::cont::Field::ASSOC_POINTS,vtkm::cont::DynamicArrayHandle(pressureArray));

  this->dataSet.AddCoordinateSystem(vtkm::cont::CoordinateSystem("coordinates",
                                                                 1,vertices));
  this->dataSet.AddField(density);
  this->dataSet.AddField(velocity_u);
  this->dataSet.AddField(velocity_v);
  this->dataSet.AddField(velocity_w);
  this->dataSet.AddField(pressure);
  this->dataSet.AddCellSet(cset);
}

//------------------------------------------------------------------------------
void PyFRData::Update()
{
}
