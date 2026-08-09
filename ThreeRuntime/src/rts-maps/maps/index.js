// Map registry — side-effect imports register all maps.

import "./helios-rift.js";
import "./lumen-basin.stub.js";
import "./orekhar-frontier.stub.js";

export { getMapDefinition, listMaps, listPlayableMaps, registerMap } from "../map-definition.js";
