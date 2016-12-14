/**
 * Copyright (c), FinancialForce.com, inc
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice, 
 *      this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *      this list of conditions and the following disclaimer in the documentation 
 *      and/or other materials provided with the distribution.
 * - Neither the name of the FinancialForce.com, inc nor the names of its contributors 
 *      may be used to endorse or promote products derived from this software without 
 *      specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

@IsTest
private with sharing class fflib_SObjectUnitOfWorkTest 
{
	// SObjects (in order of dependency) used by UnitOfWork in tests bellow	
	private static List<Schema.SObjectType> MY_SOBJECTS = 
		new Schema.SObjectType[] { 
			Product2.SObjectType, 
			PricebookEntry.SObjectType, 
			Opportunity.SObjectType, 
			OpportunityLineItem.SObjectType };

	@isTest
	private static void testUnitOfWorkNewDirtyDelete()
	{
		//create place to store Opportunities
		List<Opportunity> listOfOpportunities = new List<Opportunity>();
		// Insert Opporunities with UnitOfWork
		{
			fflib_SObjectUnitOfWork uow = new fflib_SObjectUnitOfWork(MY_SOBJECTS);
			for(Integer o=0; o<10; o++)
			{
				Opportunity opp = new Opportunity();
				opp.Name = 'UoW Test Name ' + o;
				opp.Description = 'This is a description '+ o;
				opp.StageName = 'Open';
				opp.CloseDate = System.today();
				uow.registerNew(new List<SObject>{opp});
				for(Integer i=0; i<o+1; i++)
				{
					Product2 product = new Product2();
					product.Name = opp.Name + ' : Product : ' + i;
					uow.registerNew(new List<SObject>{product});
					PricebookEntry pbe = new PricebookEntry();
					pbe.UnitPrice = 10;
					pbe.IsActive = true;
					pbe.UseStandardPrice = false;
					pbe.Pricebook2Id = Test.getStandardPricebookId();
					uow.registerNew(pbe, PricebookEntry.Product2Id, product);
					OpportunityLineItem oppLineItem = new OpportunityLineItem();
					oppLineItem.Quantity = 1;
					oppLineItem.TotalPrice = 10;
					uow.registerRelationship(oppLineItem, OpportunityLineItem.PricebookEntryId, pbe);
					uow.registerNew(oppLineItem, OpportunityLineItem.OpportunityId, opp);
				}
				listOfOpportunities.add(opp);
			}
			uow.commitWork();
		}
				
		//get Ids
		//manually create an ordered list of Ids
		List<Id> subjectOpportunityIds = new List<Id>();
		for(Opportunity subjectOpportunity : listOfOpportunities){
			subjectOpportunityIds.add(subjectOpportunity.Id);
		}
		
		// Assert Results 
		assertResults(subjectOpportunityIds);
		// TODO: Need to re-instate this check with a better approach, as it is not possible when 
		//       product triggers contribute to DML (e.g. in sample app Opportunity trigger)
		// System.assertEquals(5 /* Oddly a setSavePoint consumes a DML */, Limits.getDmlStatements());

		// Records to update
		Map<Id, Opportunity> origMapOfOpps = new Map<Id, Opportunity>([select Id, Name, Description, (Select Id, Quantity, TotalPrice from OpportunityLineItems) from Opportunity where Id in :subjectOpportunityIds]);
		
		Product2 product;
		// Update some records with UnitOfWork
		{
			fflib_SObjectUnitOfWork uow = new fflib_SObjectUnitOfWork(MY_SOBJECTS);	
			Opportunity opp = origMapOfOpps.get(subjectOpportunityIds[0]);
			opp.Description = 'This is a NEW Description';
			uow.registerDirty(new List<SObject>{opp});
			product = new Product2();
			product.Name = 'New Product: ' + opp.Id;
			uow.registerNew(new List<SObject>{product});
			PricebookEntry pbe = new PricebookEntry();
			pbe.UnitPrice = 10;
			pbe.IsActive = true;
			pbe.UseStandardPrice = false;
			pbe.Pricebook2Id = Test.getStandardPricebookId();
			uow.registerNew(pbe, PricebookEntry.Product2Id, product);
			OpportunityLineItem newOppLineItem = new OpportunityLineItem();
			origMapOfOpps.get(opp.Id).OpportunityLineItems.add(newOppLineItem);
			newOppLineItem.Quantity = 3;
			newOppLineItem.TotalPrice = 30;
			uow.registerRelationship(newOppLineItem, OpportunityLineItem.PricebookEntryId, pbe);
			uow.registerNew(newOppLineItem, OpportunityLineItem.OpportunityId, opp);
			OpportunityLineItem existingOppLine = opp.OpportunityLineItems[0];
			// Test that operations on the same object can be daisy chained, and the same object registered as dirty more than once
			// This verifies that using a Map to back the dirty records collection prevents duplicate registration.
			existingOppLine.Quantity = 2;
			uow.registerDirty(new List<SObject>{existingOppLine});
			existingOppLine.TotalPrice = 20;
			uow.registerDirty(new List<SObject>{existingOppLine});
			uow.commitWork();
		}
		
		// Assert Results
		// TODO: Need to re-instate this check with a better approach, as it is not possible when 
		//       product triggers contribute to DML (e.g. in sample app Opportunity trigger)
		// System.assertEquals(11, Limits.getDmlStatements());
		Map<Id, Opportunity> mapOfOpps = new Map<Id, Opportunity>([select Id, Name, Description, (Select Id, PricebookEntry.Product2.Name, Quantity, TotalPrice from OpportunityLineItems Order By Id) from Opportunity where Id in :origMapOfOpps.keySet()]);
		System.assertEquals(10, mapOfOpps.keySet().size());
		for(Opportunity originalOpportunity : origMapOfOpps.values()){
			System.assertEquals(originalOpportunity.Description, mapOfOpps.get(originalOpportunity.Id).Description);
			System.assertEquals(originalOpportunity.OpportunityLineItems.size(), mapOfOpps.get(originalOpportunity.id).OpportunityLineItems.size());
			for(OpportunityLineItem originalLineItem : originalOpportunity.OpportunityLineItems){
				Map<Id, OpportunityLineItem> mapOfLineItems = new Map<Id, OpportunityLineItem>(mapOfOpps.get(originalOpportunity.Id).OpportunityLineItems);
				System.assertEquals(originalLineItem.Quantity, mapOfLineItems.get(originalLineItem.Id).Quantity);
				System.assertEquals(originalLineItem.TotalPrice, mapOfLineItems.get(originalLineItem.Id).TotalPrice);
			}
		}
		/**
		System.assertEquals('This is a NEW Description', mapOfOpps.get(subjectOpportunityIds[0]).Description);
		System.assertEquals(2, mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems.size());
		// Verify that both fields were updated properly
		System.assertEquals(1, mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[0].Quantity);
		System.assertEquals(20, mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[0].TotalPrice);
		**/
		System.assertEquals('New Product: ' + subjectOpportunityIds[0], new Map<Id, OpportunityLineItem>(mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems).get(product.Id).PricebookEntry.Product2.Name);
		

		// Delete some records with the UnitOfWork
		{
			fflib_SObjectUnitOfWork uow = new fflib_SObjectUnitOfWork(MY_SOBJECTS);	
			uow.registerDeleted(new List<SObject>{mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[1].PricebookEntry.Product2}); // Delete PricebookEntry Product 
			uow.registerDeleted(new List<SObject>{mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[1].PricebookEntry}); // Delete PricebookEntry
			uow.registerDeleted(new List<SObject>{mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[1]}); // Delete OpportunityLine Item
			// Register the same deletions more than once.
			// This verifies that using a Map to back the deleted records collection prevents duplicate registration.
			uow.registerDeleted(new List<SObject>{mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[1].PricebookEntry.Product2}); // Delete PricebookEntry Product 
			uow.registerDeleted(new List<SObject>{mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[1].PricebookEntry}); // Delete PricebookEntry
			uow.registerDeleted(new List<SObject>{mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems[1]}); // Delete OpportunityLine Item
			uow.commitWork();
		}
		
		// Assert Results
		// TODO: Need to re-instate this check with a better approach, as it is not possible when 
		//       product triggers contribute to DML (e.g. in sample app Opportunity trigger)
		// System.assertEquals(15, Limits.getDmlStatements());
		mapOfOpps = new Map<Id, Opportunity>([select Id, Name, Description, (Select Id, PricebookEntry.Product2.Name, Quantity from OpportunityLineItems Order By PricebookEntry.Product2.Name) from Opportunity]);
		List<Product2> prods = [Select Id from Product2 where Name = 'UoW Test Name 0 Changed : New Product'];
		System.assertEquals(10, mapOfOpps.keySet().size());
		System.assertEquals('This is a NEW Description', mapOfOpps.get(subjectOpportunityIds[0]).Description);
		System.assertEquals(1, mapOfOpps.get(subjectOpportunityIds[0]).OpportunityLineItems.size()); // Should have deleted OpportunityLineItem added above
		System.assertEquals(0, prods.size()); // Should have deleted Product added above
	}
	
	private static void assertResults(List<Id> subjectOpportunityIds)
	{
		// Standard Assertions on tests data inserted by tests
		Map<Id, Opportunity> opps = new Map<Id, Opportunity>([select Id, Name, (Select Id from OpportunityLineItems) from Opportunity where Id in :subjectOpportunityIds]);
		System.assertEquals(10, opps.keySet().size());
		System.assertEquals(1, opps.get(subjectOpportunityIds[0]).OpportunityLineItems.size());
		System.assertEquals(2, opps.get(subjectOpportunityIds[1]).OpportunityLineItems.size());
		System.assertEquals(3, opps.get(subjectOpportunityIds[2]).OpportunityLineItems.size());
		System.assertEquals(4, opps.get(subjectOpportunityIds[3]).OpportunityLineItems.size());
		System.assertEquals(5, opps.get(subjectOpportunityIds[4]).OpportunityLineItems.size());
		System.assertEquals(6, opps.get(subjectOpportunityIds[5]).OpportunityLineItems.size());
		System.assertEquals(7, opps.get(subjectOpportunityIds[6]).OpportunityLineItems.size());
		System.assertEquals(8, opps.get(subjectOpportunityIds[7]).OpportunityLineItems.size());
		System.assertEquals(9, opps.get(subjectOpportunityIds[8]).OpportunityLineItems.size());
		System.assertEquals(10, opps.get(subjectOpportunityIds[9]).OpportunityLineItems.size());
	}

	/**
	 * Create uow with new records and commit
	 *
	 *	Testing: 
	 *
	 *		- Correct events are fired when commitWork completes successfully
	 *
	 */
	@isTest
	private static void testDerivedUnitOfWork_CommitSuccess() 
	{
		//create place to store Opportunities
		List<Opportunity> listOfOpportunities = new List<Opportunity>();
		// Insert Opporunities with UnitOfWork
		DerivedUnitOfWork uow = new DerivedUnitOfWork(MY_SOBJECTS);
		for(Integer o=0; o<10; o++)
		{
			Opportunity opp = new Opportunity();
			opp.Name = 'UoW Test Name ' + o;
			opp.StageName = 'Open';
			opp.CloseDate = System.today();
			uow.registerNew(new List<SObject>{opp});
			for(Integer i=0; i<o+1; i++)
			{
				Product2 product = new Product2();
				product.Name = opp.Name + ' : Product : ' + i;
				uow.registerNew(new List<SObject>{product});
				PricebookEntry pbe = new PricebookEntry();
				pbe.UnitPrice = 10;
				pbe.IsActive = true;
				pbe.UseStandardPrice = false;
				pbe.Pricebook2Id = Test.getStandardPricebookId();
				uow.registerNew(pbe, PricebookEntry.Product2Id, product);
				OpportunityLineItem oppLineItem = new OpportunityLineItem();
				oppLineItem.Quantity = 1;
				oppLineItem.TotalPrice = 10;
				uow.registerRelationship(oppLineItem, OpportunityLineItem.PricebookEntryId, pbe);
				uow.registerNew(oppLineItem, OpportunityLineItem.OpportunityId, opp);
			}
			listOfOpportunities.add(opp);
		}
		uow.commitWork();
		//get Ids
		//manually create an ordered list of Ids
		List<Id>  subjectOpportunityIds = new List<Id>();
		for(Opportunity subjectOpportunity : listOfOpportunities){
			subjectopportunityIds.add(subjectOpportunity.Id);
		}

		// Assert Results 
		assertResults(subjectOpportunityIds);

		assertEvents(new List<String> {
				'onCommitWorkStarting'
				, 'onDMLStarting'
				, 'onDMLFinished'
				, 'onDoWorkStarting'
				, 'onDoWorkFinished'
				, 'onCommitWorkFinishing'
				, 'onCommitWorkFinished - true'
			}
			, uow.getCommitWorkEventsFired(), new Set<Schema.SObjectType>(MY_SOBJECTS), uow.getRegisteredTypes());
	}

	/**
	 * Create uow with data that results in DML Exception
	 *
	 *	Testing: 
	 *
	 *		- Correct events are fired when commitWork fails during DML processing
	 *
	 */
	@isTest
	private static void testDerivedUnitOfWork_CommitDMLFail() 
	{
		// Insert Opporunities with UnitOfWork forcing a failure on DML by not setting 'Name' field
		DerivedUnitOfWork uow = new DerivedUnitOfWork(MY_SOBJECTS);
		Opportunity opp = new Opportunity();
		uow.registerNew(new List<SObject>{opp});
		Boolean didFail = false;
		System.DmlException caughtEx = null;

		try {
			uow.commitWork();    
		}
		catch (System.DmlException dmlex) {
			didFail = true;
			caughtEx = dmlex;
		}	
		
		// Assert Results 
		System.assertEquals(didFail, true, 'didFail');
		System.assert(caughtEx.getMessage().contains('REQUIRED_FIELD_MISSING'), String.format('Exception message was ', new List<String> { caughtEx.getMessage() }));

		assertEvents(new List<String> { 
				'onCommitWorkStarting'
				, 'onDMLStarting'
				, 'onCommitWorkFinished - false' 
			}
			, uow.getCommitWorkEventsFired(), new Set<Schema.SObjectType>(MY_SOBJECTS), uow.getRegisteredTypes());
	}

	/**
	 * Create uow with work that fails
	 *
	 *	Testing: 
	 *
	 *		- Correct events are fired when commitWork fails during DoWork processing
	 *
	 */
	@isTest
	private static void testDerivedUnitOfWork_CommitDoWorkFail() 
	{
		// Insert Opporunities with UnitOfWork
		DerivedUnitOfWork uow = new DerivedUnitOfWork(MY_SOBJECTS);
		Opportunity opp = new Opportunity();
		opp.Name = 'UoW Test Name 1';
		opp.StageName = 'Open';
		opp.CloseDate = System.today();
		uow.registerNew(new List<SObject>{opp});

		// register work that will fail during processing
		FailDoingWork fdw = new FailDoingWork();
		uow.registerWork(fdw);

		Boolean didFail = false;
		FailDoingWorkException caughtEx = null;

		try {
			uow.commitWork();    
		}
		catch (FailDoingWorkException fdwe) {
			didFail = true;
			caughtEx = fdwe;
		}	
		
		// Assert Results 
		System.assertEquals(didFail, true, 'didFail');
		System.assert(caughtEx.getMessage().contains('Work failed.'), String.format('Exception message was ', new List<String> { caughtEx.getMessage() }));

		assertEvents(new List<String> { 
				'onCommitWorkStarting'
				, 'onDMLStarting'
				, 'onDMLFinished'
				, 'onDoWorkStarting'
				, 'onCommitWorkFinished - false' 
			}
			, uow.getCommitWorkEventsFired(), new Set<Schema.SObjectType>(MY_SOBJECTS), uow.getRegisteredTypes());
	}	

	/**
	 * Assert that actual events exactly match expected events (size, order and name)
	 * and types match expected types
	 */
	private static void assertEvents(List<String> expectedEvents, List<String> actualEvents, Set<Schema.SObjectType> expectedTypes, Set<Schema.SObjectType> actualTypes) 
	{
		// assert that events match
		System.assertEquals(expectedEvents.size(), actualEvents.size(), 'events size');
		for (Integer i = 0; i < expectedEvents.size(); i++)
		{
			System.assertEquals(expectedEvents[i], actualEvents[i], String.format('Event {0} was not fired in order expected.', new List<String> { expectedEvents[i] }));
		}

		// assert that types match
		System.assertEquals(expectedTypes.size(), actualTypes.size(), 'types size');
		for (Schema.SObjectType sObjectType :expectedTypes)
		{
			System.assertEquals(true, actualTypes.contains(sObjectType), String.format('Type {0} was not registered.', new List<String> { sObjectType.getDescribe().getName() }));	
		}
	}

	/**
	 * DoWork implementation that throws exception during processing
	 */
	private class FailDoingWork implements fflib_SObjectUnitOfWork.IDoWork
	{
		public void doWork()
		{
			throw new FailDoingWorkException('Work failed.');
		}
	}

	/**
	 * Derived unit of work that tracks event notifications and handle registration of type
	 */
	private class DerivedUnitOfWork extends fflib_SObjectUnitOfWork
	{
		private List<String> m_commitWorkEventsFired = new List<String>();
		private Set<Schema.SObjectType> m_registeredTypes = new Set<Schema.SObjectType>();

		public List<String> getCommitWorkEventsFired()
		{
			return m_commitWorkEventsFired.clone();
		}

		public Set<Schema.SObjectType> getRegisteredTypes()
		{
			return m_registeredTypes.clone();
		}

		public DerivedUnitOfWork(List<Schema.SObjectType> sObjectTypes)
		{
			super(sObjectTypes);
		}

		public DerivedUnitOfWork(List<Schema.SObjectType> sObjectTypes, IDML dml)
		{
			super(sObjectTypes, dml);
		}

		private void addEvent(String event) 
		{
			// events should only be fired one time
			// ensure that this event has not been fired already
			for (String eventName :m_commitWorkEventsFired)
			{
				if (event == eventName)
				{
					throw new DerivedUnitOfWorkException(String.format('Event {0} has already been fired.', new List<String> { event }));	
				}
			}
			m_commitWorkEventsFired.add(event);
		}

		public override void onRegisterType(Schema.SObjectType sObjectType)
		{
			if (m_registeredTypes.contains(sObjectType))
			{
				throw new DerivedUnitOfWorkException(String.format('Type {0} has already been registered.', new List<String> { sObjectType.getDescribe().getName() }));
			}
			m_registeredTypes.add(sObjectType);
		}

		public override void onCommitWorkStarting()
		{
			addEvent('onCommitWorkStarting');
		}

		public override void onDMLStarting()
		{
			addEvent('onDMLStarting');
		}

		public override void onDMLFinished()
		{
			addEvent('onDMLFinished');
		}		

		public override void onDoWorkStarting()
		{
			addEvent('onDoWorkStarting');
		}

		public override void onDoWorkFinished()
		{
			addEvent('onDoWorkFinished');
		}		

		public override void onCommitWorkFinishing()
		{
			addEvent('onCommitWorkFinishing');
		}

		public override void onCommitWorkFinished(Boolean wasSuccessful)
		{
			addEvent('onCommitWorkFinished - ' + wasSuccessful);
		}
	}

	public class DerivedUnitOfWorkException extends Exception {}
	public class FailDoingWorkException extends Exception {}
}