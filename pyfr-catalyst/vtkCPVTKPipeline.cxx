#include "vtkCPVTKPipeline.h"

#include <vtkCommunicator.h>
#include <vtkCompleteArrays.h>
#include <vtkCPDataDescription.h>
#include <vtkDataArray.h>
#include <vtkCPInputDataDescription.h>
#include <vtkMultiProcessController.h>
#include <vtkNew.h>
#include <vtkObjectFactory.h>
#include <vtkPointData.h>
#include <vtkPVArrayCalculator.h>
#include <vtkPVTrivialProducer.h>
#include <vtkSMProxyManager.h>
#include <vtkThreshold.h>
#include <vtkUnstructuredGrid.h>
#include <vtkXMLPUnstructuredGridWriter.h>

#include <string>
#include <sstream>

vtkStandardNewMacro(vtkCPVTKPipeline);

//----------------------------------------------------------------------------
vtkCPVTKPipeline::vtkCPVTKPipeline()
{
}

//----------------------------------------------------------------------------
vtkCPVTKPipeline::~vtkCPVTKPipeline()
{
}

//----------------------------------------------------------------------------
void vtkCPVTKPipeline::Initialize(char* fileName)
{
  this->FileName = std::string(fileName);
}

//----------------------------------------------------------------------------
int vtkCPVTKPipeline::RequestDataDescription(
  vtkCPDataDescription* dataDescription)
{
  if(!dataDescription)
    {
    vtkWarningMacro("dataDescription is NULL.");
    return 0;
    }

  if(this->FileName.empty())
    {
    vtkWarningMacro("No output file name given to output results to.");
    return 0;
    }

  dataDescription->GetInputDescriptionByName("input")->AllFieldsOn();
  dataDescription->GetInputDescriptionByName("input")->GenerateMeshOn();
  return 1;
}

//----------------------------------------------------------------------------
int vtkCPVTKPipeline::CoProcess(
  vtkCPDataDescription* dataDescription)
{
  if(!dataDescription)
    {
    vtkWarningMacro("DataDescription is NULL");
    return 0;
    }
  vtkUnstructuredGrid* grid = vtkUnstructuredGrid::SafeDownCast(
    dataDescription->GetInputDescriptionByName("input")->GetGrid());
  if(grid == NULL)
    {
    vtkWarningMacro("DataDescription is missing input unstructured grid.");
    return 0;
    }
  if(this->RequestDataDescription(dataDescription) == 0)
    {
    return 1;
    }

  vtkNew<vtkPVTrivialProducer> producer;
  producer->SetOutput(grid);

  vtkNew<vtkPVArrayCalculator> calculator;
  calculator->SetInputConnection(producer->GetOutputPort());
  calculator->SetAttributeMode(1);
  calculator->SetResultArrayName("velocity magnitude");
  calculator->SetFunction("mag(velocity)");

  // update now so that we can get the global data bounds of
  // the velocity magnitude for thresholding
  calculator->Update();
  double range[2];
  vtkUnstructuredGrid::SafeDownCast(calculator->GetOutput())->GetPointData()
    ->GetArray("velocity magnitude")->GetRange(range, 0);
  double globalRange[2];
  vtkMultiProcessController::GetGlobalController()->AllReduce(
    range+1, globalRange+1, 1, vtkCommunicator::MAX_OP);

  vtkNew<vtkThreshold> threshold;
  threshold->SetInputConnection(calculator->GetOutputPort());
  threshold->SetInputArrayToProcess(
    0, 0, 0, "vtkDataObject::FIELD_ASSOCIATION_POINTS", "velocity magnitude");
  threshold->ThresholdBetween(0.9*globalRange[1], globalRange[1]);

  // If process 0 doesn't have any points or cells, the writer may
  // have problems in parallel so we use completeArrays to fill in
  // the missing information.
  vtkNew<vtkCompleteArrays> completeArrays;
  completeArrays->SetInputConnection(threshold->GetOutputPort());

  vtkNew<vtkXMLPUnstructuredGridWriter> writer;
  writer->SetInputConnection(completeArrays->GetOutputPort());
  std::ostringstream o;
  o << dataDescription->GetTimeStep();
  std::string name = this->FileName + o.str() + ".pvtu";
  writer->SetFileName(name.c_str());
  writer->Update();

  return 1;
}

//----------------------------------------------------------------------------
void vtkCPVTKPipeline::PrintSelf(ostream& os, vtkIndent indent)
{
  this->Superclass::PrintSelf(os, indent);
  os << indent << "FileName: " << this->FileName << "\n";
}
