// SPDX-License-Identifier: MIT
pragma solidity >=0.5.9;

import "./Equation.sol";

contract FunctionMinimization {
    using Equation for Equation.Node[];

    struct FunctionEntry {

        Equation.Node[] equation;
        Equation.Node[] derivada;
        uint256 reward;
        address payable publisher;
        bool rewardPaid; 
        uint endBlock;
    }

    struct SubmitionEntry{
        address payable submitter;
        uint256 point; 
        uint currentBlock;
    } 

    FunctionEntry[] public functions;
    mapping (uint=>SubmitionEntry[]) public submission;

    function publishFunction(uint256[] memory expressions_equation, uint256[] memory expressions_derivada, uint tiempo) public payable {
        // Añadir una nueva entrada vacía al array 'functions'
        functions.push();
        uint256 functionIndex = functions.length - 1;

        // Configurar la nueva entrada

        FunctionEntry storage newEntry = functions[functionIndex];

        newEntry.reward = msg.value;  // Utiliza el valor enviado como recompensa
        newEntry.publisher = payable(msg.sender);
        newEntry.endBlock = block.number + tiempo; // Cuanto tiempo va a estar disponible la entrega de mínimos
        // Inicializar la función con el array de expresiones proporcionado
        Equation.init(newEntry.equation, expressions_equation);
        // Inicializar la derivada con el array de expresiones proporcionado
        Equation.init(newEntry.derivada, expressions_derivada);
    }


    function submitMinimum(uint256 functionId, uint256 minimum) external payable{
        require(functionId < functions.length, "ID de funcion invalido");

        FunctionEntry storage funcEntry = functions[functionId];

        require(funcEntry.endBlock >= block.number, "Ya cerro la subasta");
        require(!funcEntry.rewardPaid, "Ya ha sido pagada la recompensa de esta funcion");

        // Evaluamos que sea un punto critico
        uint256 evaluatedValue = funcEntry.derivada.calculate(minimum);
        require(evaluatedValue == 0, "No es un punto critico, busque uno que si lo sea.");
        
        SubmitionEntry memory newEntry = SubmitionEntry(payable(msg.sender),evaluatedValue, block.number);
        submission[functionId].push(newEntry);
    }


    function claimReward(uint256 functionId) external payable{
        require(functionId < functions.length, "ID de funcion invalido, fuera de indice.");
        FunctionEntry storage funcEntry = functions[functionId]; //Se recupera la funcion en cuestion
        require(funcEntry.endBlock < block.number, "La subasta sigue abierta");
        require(!funcEntry.rewardPaid,  "Ya ha sido pagada la recompensa de esta funcion");// Verificar que la recompensa aún no haya sido pagada
        address bestSubmitter;
        uint256 best_minimum; 
        uint256 current_minimum;
        uint arrayLength = submission[functionId].length;
        for (uint i=0; i<arrayLength; i++) {
            current_minimum = submission[functionId][i].point;
            if (current_minimum < best_minimum)
            {
                best_minimum = current_minimum;
                bestSubmitter = submission[functionId][i].submitter;
            }
        }
        // Verificar que hay suficiente balance en el contrato para pagar la recompensa
        require(address(this).balance >= funcEntry.reward, "Insufficient balance in contract");
        // Transfiere la recompensa al remitente y marca como pagada
        if(bestSubmitter == msg.sender){
            payable(msg.sender).transfer(funcEntry.reward);
            funcEntry.rewardPaid = true; // Marcar la recompensa como pagada
        }
    }

  // The receive function is called when Ether is sent to the contract with no calldata
    receive() external payable {
        // Logic to handle plain Ether transfers, if any
    }

    // The fallback function is called when a function that doesn't exist is called or when Ether is sent with calldata
    fallback() external payable {
        // Logic to handle calls to non-existent functions, if any
    }
}