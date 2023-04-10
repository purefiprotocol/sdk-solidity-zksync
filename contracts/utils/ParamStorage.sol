// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

abstract contract ParamStorage{

  mapping (uint16 => address) internal addressParams;
  mapping (uint16 => uint256) internal uintParams;
  mapping (uint16 => string) internal stringParams;

  event AddressValueChanged(uint16 key, address oldValue, address newValue);
  event UintValueChanged(uint16 key, uint256 oldValue, uint256 newValue);
  event StringValueChanged(uint16 key, string oldValue, string newValue);

  // ************ PUBLIC GETTER FUNCTIONS ******************

  function getAddress(uint16 key) external view returns (address){
    return addressParams[key];
  }

  function getUint256(uint16 key) external view returns (uint256){
    return uintParams[key];
  }

  function getString(uint16 key) external view returns (string memory){
    return stringParams[key];
  }
  
  // ************ ADMIN FUNCTIONS ******************
  function setAddress(uint16 _key, address _value) external {
    require(_authorizeSetter(msg.sender), "ParamStorage: setter unauthorized");
    address oldValue = addressParams[_key];
    addressParams[_key] = _value;
    emit AddressValueChanged(_key, oldValue, addressParams[_key]);
  }

  function setUint256(uint16 _key, uint256 _value) external {
    require(_authorizeSetter(msg.sender), "ParamStorage: setter unauthorized");
    uint256 oldValue = uintParams[_key];
    uintParams[_key] = _value;
    emit UintValueChanged(_key, oldValue, uintParams[_key]);
  }

  function setString(uint16 _key, string memory _value) external {
    require(_authorizeSetter(msg.sender), "ParamStorage: setter unauthorized");
    string memory oldValue = stringParams[_key];
    stringParams[_key] = _value;
    emit StringValueChanged(_key, oldValue, stringParams[_key]);
  }

  function _authorizeSetter(address _setter) internal virtual view returns (bool);

}
